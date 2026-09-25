import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

import 'line_geo.dart';

/// Result of projecting a fix onto a multi-leg path.
class PathProjection {
  final int legIndex;
  final double crossTrackM;
  final double alongPathM;
  final double remainingM;
  final double totalM;
  final ll.LatLng projected;
  final double segmentBearingDeg;
  final String segmentLabel;
  final double alongSegmentM;
  final double segmentLengthM;
  final bool pastEnd;
  final bool interior;

  const PathProjection({
    required this.legIndex,
    required this.crossTrackM,
    required this.alongPathM,
    required this.remainingM,
    required this.totalM,
    required this.projected,
    required this.segmentBearingDeg,
    required this.segmentLabel,
    required this.alongSegmentM,
    required this.segmentLengthM,
    required this.pastEnd,
    required this.interior,
  });

  double get progressFraction =>
      totalM <= 0 ? 0.0 : (alongPathM / totalM).clamp(0.0, 1.0);
}

/// Multi-leg projector with switchCost scoring and dwell before leg change.
///
/// Scoring (Qwen LineRunner): for each leg, score =
///   (interior ? |lateral| : distToClampedFoot) + (leg == hint ? 0 : switchCost).
/// A candidate leg must win for [dwellFixes] consecutive updates before the
/// active leg commits (reduces flicker near bends).
///
/// Exception: if the active leg is already exterior and another leg is
/// interior by a wide margin (well past the bend, not the ±switchCost
/// dither), commit immediately. Waiting out the dwell there shows cross-track
/// against the previous leg and reads as the wrong side.
class LineProjector {
  static const double defaultSwitchCostM = 2.5;
  static const int defaultDwellFixes = 2;

  /// Metres beyond the last vertex before the walk is "past the end".
  /// A fraction of segment length (the old `t > 0.98` rule) fired tens of
  /// metres early on a long pipe run.
  static const double pastEndMarginM = 8.0;

  int _activeLeg = 0;
  int? _pendingLeg;
  int _pendCount = 0;

  int get activeLeg => _activeLeg;

  void reset({int leg = 0}) {
    _activeLeg = leg;
    _pendingLeg = null;
    _pendCount = 0;
  }

  /// Project [cur] onto [points] (length ≥ 2).
  ///
  /// [labels] optional per-vertex labels for segmentLabel.
  PathProjection? project(
    ll.LatLng cur,
    List<ll.LatLng> points, {
    List<String?>? labels,
    double switchCostM = defaultSwitchCostM,
    int dwellFixes = defaultDwellFixes,
    bool commitDwell = true,
  }) {
    if (points.length < 2) return null;

    final origin = points.first;
    final nSeg = points.length - 1;
    final projs = <SegProjection>[];
    final lens = <double>[];
    for (var i = 0; i < nSeg; i++) {
      final pr = projectSegmentEnu(
        origin: origin,
        p: cur,
        a: points[i],
        b: points[i + 1],
      );
      projs.add(pr);
      lens.add(pr.lengthM);
    }

    if (_activeLeg < 0 || _activeLeg >= nSeg) {
      _activeLeg = _activeLeg.clamp(0, nSeg - 1);
    }

    var best = _activeLeg;
    var bestScore = double.infinity;
    for (var i = 0; i < nSeg; i++) {
      final pr = projs[i];
      final base = pr.interior ? pr.lateralM.abs() : pr.distToSegM;
      final score = base + (i == _activeLeg ? 0.0 : switchCostM);
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }

    if (commitDwell) {
      final activePr = projs[_activeLeg];
      final bestPr = projs[best];
      final decisive = best != _activeLeg &&
          !activePr.interior &&
          bestPr.interior &&
          activePr.distToSegM > switchCostM * 3 &&
          bestPr.lateralM.abs() + 1.0 < activePr.distToSegM;
      if (decisive) {
        _activeLeg = best;
        _pendingLeg = null;
        _pendCount = 0;
      } else if (best != _activeLeg) {
        if (_pendingLeg == best) {
          _pendCount++;
          if (_pendCount >= dwellFixes) {
            _activeLeg = best;
            _pendingLeg = null;
            _pendCount = 0;
          }
        } else {
          _pendingLeg = best;
          _pendCount = 1;
        }
      } else {
        _pendingLeg = null;
        _pendCount = 0;
      }
    } else {
      _activeLeg = best;
    }

    // Display projection always on committed active leg (with hint scoring).
    return _buildResult(
      cur: cur,
      points: points,
      labels: labels,
      leg: _activeLeg,
      projs: projs,
      lens: lens,
      origin: origin,
    );
  }

  /// One-shot projection without mutating dwell state (tests / map overlay).
  static PathProjection? projectOnce(
    ll.LatLng cur,
    List<ll.LatLng> points, {
    List<String?>? labels,
    int hintLeg = 0,
    double switchCostM = defaultSwitchCostM,
  }) {
    final p = LineProjector().._activeLeg = hintLeg;
    return p.project(
      cur,
      points,
      labels: labels,
      switchCostM: switchCostM,
      commitDwell: false,
    );
  }

  PathProjection _buildResult({
    required ll.LatLng cur,
    required List<ll.LatLng> points,
    required List<String?>? labels,
    required int leg,
    required List<SegProjection> projs,
    required List<double> lens,
    required ll.LatLng origin,
  }) {
    final pr = projs[leg];
    var cum = 0.0;
    for (var i = 0; i < leg; i++) {
      cum += lens[i];
    }
    final total = lens.fold<double>(0, (s, l) => s + l);
    final along = cum + pr.tClamped * pr.lengthM;
    final remaining = max(0.0, total - along);

    final a = points[leg];
    final b = points[leg + 1];
    final projected = LineGeo.fromEnu(
      origin,
      LineGeo.toEnu(origin, a).e +
          pr.tClamped *
              (LineGeo.toEnu(origin, b).e - LineGeo.toEnu(origin, a).e),
      LineGeo.toEnu(origin, a).n +
          pr.tClamped *
              (LineGeo.toEnu(origin, b).n - LineGeo.toEnu(origin, a).n),
    );

    // Prefer spherical XT for display consistency with unit tests / docs.
    final xt = LineGeo.crossTrackM(cur, a, b);
    final beyondM = (pr.t - 1.0) * pr.lengthM;
    final pastEnd = leg == lens.length - 1 && beyondM > pastEndMarginM;

    return PathProjection(
      legIndex: leg,
      crossTrackM: xt,
      alongPathM: along,
      remainingM: remaining,
      totalM: total,
      projected: projected,
      segmentBearingDeg: LineGeo.bearingDeg(a, b),
      segmentLabel: _segLabel(points, labels, leg),
      alongSegmentM: pr.tClamped * pr.lengthM,
      segmentLengthM: pr.lengthM,
      pastEnd: pastEnd,
      interior: pr.interior,
    );
  }

  static String _segLabel(
    List<ll.LatLng> points,
    List<String?>? labels,
    int leg,
  ) {
    String name(int i) {
      if (labels != null && i < labels.length && labels[i] != null) {
        return labels[i]!;
      }
      if (i <= 0) return 'Start';
      if (i >= points.length - 1) return 'End';
      return 'Via $i';
    }

    return '${name(leg)} → ${name(leg + 1)}';
  }
}
