import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

import 'line_geo.dart';

/// Corridor half-width: max(userBaseTol, k * accuracy), clamped.
class Corridor {
  static const double defaultBaseTolM = 1.8;
  static const double defaultAccuracyFactor = 0.6;
  static const double minTolM = 0.5;
  static const double maxTolM = 12.0;

  /// Effective half-width of the "on line" band.
  static double halfWidthM({
    double baseTolM = defaultBaseTolM,
    double? accuracyM,
    double accuracyFactor = defaultAccuracyFactor,
  }) {
    final acc = accuracyM ?? 0.0;
    final raw = max(baseTolM, accuracyFactor * acc);
    return raw.clamp(minTolM, maxTolM);
  }

  /// Buffer [path] by [halfWidthM] on both sides → closed polygon ring.
  /// DeepSeek/dump3 style: offset each vertex perpendicular to local bearing.
  static List<ll.LatLng> polygon(List<ll.LatLng> path, double halfWidthM) {
    if (path.length < 2 || halfWidthM <= 0) return const [];
    final left = <ll.LatLng>[];
    final right = <ll.LatLng>[];
    for (var i = 0; i < path.length; i++) {
      final prev = path[max(0, i - 1)];
      final next = path[min(path.length - 1, i + 1)];
      final brg = LineGeo.bearingDeg(prev, next);
      left.add(LineGeo.destination(path[i], (brg + 270) % 360, halfWidthM));
      right.add(LineGeo.destination(path[i], (brg + 90) % 360, halfWidthM));
    }
    return [...left, ...right.reversed];
  }
}

/// Stops the on-line band and the map corridor from jumping when a single
/// GPS accuracy sample spikes. Widens faster than it shrinks: a bad fix
/// must not hide a real offset, and a good fix must not snap the polygon shut.
class CorridorWidthFilter {
  double? _width;

  static const double widenStepM = 1.2;
  static const double shrinkStepM = 0.25;

  double? get width => _width;

  void reset() => _width = null;

  /// User tapped ± corridor — follow immediately.
  double snap(double next) {
    _width = next;
    return next;
  }

  double update(double next) {
    final prev = _width;
    if (prev == null) {
      _width = next;
      return next;
    }
    final step = next > prev ? widenStepM : shrinkStepM;
    final delta = (next - prev).clamp(-step, step);
    _width = prev + delta;
    return _width!;
  }
}
