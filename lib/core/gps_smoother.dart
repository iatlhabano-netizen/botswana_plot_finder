import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

import 'line_geo.dart';

/// Accuracy-weighted Kalman-lite filter on a local ENU tangent plane.
///
/// Blends dump2/Qwen grace (hold on small jumps) with catch-up (raise alpha /
/// snap on large teleports). Poor accuracy → trust prediction more.
class GpsSmoother {
  double _e = 0;
  double _n = 0;
  double _ve = 0;
  double _vn = 0;
  ll.LatLng? _origin;
  int _lastTMs = 0;
  bool _initialized = false;
  double _accuracy = 50;
  int _holdCount = 0;

  /// Brief hold when a modest jump appears (grace), then accept.
  static const int jumpHoldFixes = 2;
  static const double jumpHoldM = 25;

  ll.LatLng? get origin => _origin;
  double get smoothedAccuracyM => _accuracy;

  SmoothedFix? update(ll.LatLng raw, double accuracyM, int timeMs) {
    final acc = max(1.0, accuracyM);

    if (!_initialized || _origin == null) {
      _origin = raw;
      _e = 0;
      _n = 0;
      _ve = 0;
      _vn = 0;
      _lastTMs = timeMs;
      _accuracy = acc;
      _initialized = true;
      _holdCount = 0;
      return SmoothedFix(position: raw, accuracyM: acc, speedMps: 0);
    }

    var dt = (timeMs - _lastTMs) / 1000.0;
    if (dt < 0.1) dt = 0.1;
    if (dt > 10) dt = 10;
    _lastTMs = timeMs;

    final en = LineGeo.toEnu(_origin!, raw);
    if (en.e.abs() > 5000 || en.n.abs() > 5000) {
      _origin = raw;
      _e = 0;
      _n = 0;
      _ve = 0;
      _vn = 0;
      _holdCount = 0;
      return SmoothedFix(position: raw, accuracyM: acc, speedMps: 0);
    }

    // Predict
    _e += _ve * dt;
    _n += _vn * dt;

    final jump = sqrt(pow(en.e - _e, 2) + pow(en.n - _n, 2));

    // Teleport / reacquire — snap immediately.
    if (jump > max(100.0, acc * 10)) {
      _e = en.e;
      _n = en.n;
      _ve = 0;
      _vn = 0;
      _accuracy = acc;
      _holdCount = 0;
    } else if (jump > max(jumpHoldM, acc * 3) && _holdCount < jumpHoldFixes) {
      // Grace: hold estimate briefly, raise catch-up pressure next fixes.
      _holdCount++;
      _accuracy = 0.85 * _accuracy + 0.15 * acc;
    } else {
      _holdCount = 0;
      // Higher alpha (=k) when accuracy is good; raise further after a hold.
      var k = (1.6 / acc).clamp(0.12, 0.85);
      if (jump > jumpHoldM) k = min(0.95, k + 0.25); // catch-up
      final re = en.e - _e;
      final rn = en.n - _n;
      _e += k * re;
      _n += k * rn;
      _ve = 0.7 * _ve + 0.3 * (k * re / dt);
      _vn = 0.7 * _vn + 0.3 * (k * rn / dt);
      _accuracy = 0.7 * _accuracy + 0.3 * acc;
    }

    return SmoothedFix(
      position: LineGeo.fromEnu(_origin!, _e, _n),
      accuracyM: _accuracy,
      speedMps: sqrt(_ve * _ve + _vn * _vn),
    );
  }

  void reset() {
    _initialized = false;
    _origin = null;
    _holdCount = 0;
  }
}

class SmoothedFix {
  final ll.LatLng position;
  final double accuracyM;
  final double speedMps;

  const SmoothedFix({
    required this.position,
    required this.accuracyM,
    required this.speedMps,
  });
}

/// Separate EMA for display of cross-track / along-track.
class DualEma {
  double? cross;
  double? along;

  static const double crossAlpha = 0.35;
  static const double alongAlpha = 0.45;

  void reset() {
    cross = null;
    along = null;
  }

  ({double cross, double along}) update(double nextCross, double nextAlong) {
    cross = cross == null ? nextCross : cross! + (nextCross - cross!) * crossAlpha;
    along = along == null ? nextAlong : along! + (nextAlong - along!) * alongAlpha;
    return (cross: cross!, along: along!);
  }
}
