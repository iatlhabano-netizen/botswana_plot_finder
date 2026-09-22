import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

import 'path_guidance.dart';

/// One vertex on a guided pipe/fence path (start, via, or end).
class PathVertex {
  final ll.LatLng point;
  final String? label;

  const PathVertex(this.point, {this.label});

  Map<String, dynamic> toJson() => {
        'lat': point.latitude,
        'lng': point.longitude,
        if (label != null) 'label': label,
      };

  factory PathVertex.fromJson(Map<String, dynamic> j) => PathVertex(
        ll.LatLng(
          (j['lat'] as num).toDouble(),
          (j['lng'] as num).toDouble(),
        ),
        label: j['label'] as String?,
      );

  PathVertex copyWith({ll.LatLng? point, String? label}) =>
      PathVertex(point ?? this.point, label: label ?? this.label);
}

/// Ordered multi-segment path for stay-on-line guidance (pipes, fence, utilities).
class GuidedPath {
  final List<PathVertex> vertices;

  const GuidedPath(this.vertices);

  factory GuidedPath.fromPoints(
    List<ll.LatLng> points, {
    List<String?>? labels,
  }) {
    assert(points.length >= 2);
    final verts = <PathVertex>[];
    for (var i = 0; i < points.length; i++) {
      final label = labels != null && i < labels.length ? labels[i] : null;
      verts.add(PathVertex(points[i], label: label));
    }
    return GuidedPath(verts);
  }

  factory GuidedPath.startEnd(
    ll.LatLng start,
    ll.LatLng end, {
    String? startLabel,
    String? endLabel,
  }) =>
      GuidedPath([
        PathVertex(start, label: startLabel ?? 'Start'),
        PathVertex(end, label: endLabel ?? 'End'),
      ]);

  bool get isValid => vertices.length >= 2;

  int get segmentCount => max(0, vertices.length - 1);

  List<ll.LatLng> get points =>
      vertices.map((v) => v.point).toList(growable: false);

  /// Length of segment [i] (vertex i → i+1).
  double segmentLengthM(int i) {
    assert(i >= 0 && i < segmentCount);
    return PathGuidance.distanceM(vertices[i].point, vertices[i + 1].point);
  }

  /// Total geodesic length of all segments.
  double get totalLengthM {
    var sum = 0.0;
    for (var i = 0; i < segmentCount; i++) {
      sum += segmentLengthM(i);
    }
    return sum;
  }

  /// Cumulative length from path start up to the start of segment [i].
  double lengthBeforeSegment(int i) {
    var sum = 0.0;
    for (var j = 0; j < i && j < segmentCount; j++) {
      sum += segmentLengthM(j);
    }
    return sum;
  }

  String defaultVertexLabel(int i) {
    if (i <= 0) return vertices[i].label ?? 'Start';
    if (i >= vertices.length - 1) {
      return vertices[i].label ?? 'End';
    }
    return vertices[i].label ?? 'Via $i';
  }

  String segmentLabel(int i) {
    if (i < 0 || i >= segmentCount) return '';
    return '${defaultVertexLabel(i)} → ${defaultVertexLabel(i + 1)}';
  }

  Map<String, dynamic> toJson() => {
        'vertices': vertices.map((v) => v.toJson()).toList(),
      };

  factory GuidedPath.fromJson(Map<String, dynamic> j) {
    final list = (j['vertices'] as List)
        .map((e) => PathVertex.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return GuidedPath(list);
  }

  /// Project [cur] onto the path: best segment by min distance-to-segment,
  /// preferring interior projections (|cross-track| when along-track in range).
  PathFix evaluate(ll.LatLng cur, {double endpointMarginM = 20.0}) {
    assert(isValid);
    var bestScore = double.infinity;
    var bestSeg = 0;
    var bestXt = 0.0;
    var bestAlong = 0.0;
    var bestSegLen = segmentLengthM(0);

    for (var i = 0; i < segmentCount; i++) {
      final a = vertices[i].point;
      final b = vertices[i + 1].point;
      final segLen = PathGuidance.distanceM(a, b);
      if (segLen < 0.01) continue;

      final along = PathGuidance.alongTrackM(cur, a, b);
      final xt = PathGuidance.crossTrackM(cur, a, b);

      // Distance from point to finite segment (geodesic approximation).
      final double score;
      if (along >= -endpointMarginM && along <= segLen + endpointMarginM) {
        // Prefer in-range / near-range by |XT|, with small penalty outside.
        final outside = along < 0
            ? -along
            : (along > segLen ? along - segLen : 0.0);
        score = xt.abs() + outside * 0.5;
      } else if (along < 0) {
        score = PathGuidance.distanceM(cur, a);
      } else {
        score = PathGuidance.distanceM(cur, b);
      }

      if (score < bestScore) {
        bestScore = score;
        bestSeg = i;
        bestXt = xt;
        bestAlong = along;
        bestSegLen = segLen;
      }
    }

    final clampedAlong = bestAlong.clamp(0.0, bestSegLen);
    final progress = lengthBeforeSegment(bestSeg) + clampedAlong;
    final total = totalLengthM;
    final remaining = max(0.0, total - progress);

    final pastEnd = bestSeg == segmentCount - 1 && bestAlong > bestSegLen - 0.5;

    final a = vertices[bestSeg].point;
    final b = vertices[bestSeg + 1].point;
    // Desired bearing: along active segment toward next vertex.
    // If behind start of segment, still aim along segment; if past end of
    // last segment, bearing back toward end.
    final double bearing;
    if (pastEnd) {
      bearing = PathGuidance.bearingDeg(b, a); // turn back
    } else {
      bearing = PathGuidance.bearingDeg(a, b);
    }

    return PathFix(
      segmentIndex: bestSeg,
      crossTrackM: bestXt,
      alongSegmentM: bestAlong,
      segmentLengthM: bestSegLen,
      alongPathM: progress,
      remainingM: remaining,
      totalLengthM: total,
      pastEnd: pastEnd,
      desiredBearingDeg: bearing,
      segmentLabel: segmentLabel(bestSeg),
    );
  }
}

/// Result of projecting a GPS fix onto a [GuidedPath].
class PathFix {
  final int segmentIndex;
  final double crossTrackM;
  final double alongSegmentM;
  final double segmentLengthM;
  final double alongPathM;
  final double remainingM;
  final double totalLengthM;
  final bool pastEnd;
  final double desiredBearingDeg;
  final String segmentLabel;

  const PathFix({
    required this.segmentIndex,
    required this.crossTrackM,
    required this.alongSegmentM,
    required this.segmentLengthM,
    required this.alongPathM,
    required this.remainingM,
    required this.totalLengthM,
    required this.pastEnd,
    required this.desiredBearingDeg,
    required this.segmentLabel,
  });

  double get progressFraction =>
      totalLengthM <= 0 ? 0.0 : (alongPathM / totalLengthM).clamp(0.0, 1.0);
}

/// Light in-app "job" (optional SharedPreferences persistence).
class LineJob {
  final String id;
  final String label;
  final GuidedPath path;
  final DateTime createdAt;

  const LineJob({
    required this.id,
    required this.label,
    required this.path,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'path': path.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory LineJob.fromJson(Map<String, dynamic> j) => LineJob(
        id: j['id'] as String,
        label: j['label'] as String? ?? 'Job',
        path: GuidedPath.fromJson(Map<String, dynamic>.from(j['path'] as Map)),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
