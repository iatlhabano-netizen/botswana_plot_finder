import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

import 'line_geo.dart';

/// Accuracy-weighted Kalman-lite filter on a local ENU tangent plane.
///
/// Blends dump2/Qwen grace (hold on small jumps) with catch-up (raise alpha /
/// snap on large teleports). Poor accuracy → trust prediction more.
///
/// A grace hold does **not** keep integrating velocity — that was launching
/// the estimate away from the last good fix. Velocity inferred from a
/// sub-second innovation is clamped so one noisy sample cannot imply a sprint.
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
  SmoothedFix? _last;

  /// Brief hold when a modest jump appears (grace), then accept.
  static const int jumpHoldFixes = 2;
  static const double jumpHoldM = 25;

  /// Cap inferred speed. Kills 50 m/s spikes from a bad innovation / tiny dt
  /// without freezing a vehicle on a farm track (~12 m/s ≈ 43 km/h).
  static const double maxSpeedMps = 12;

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
      return _last =
          SmoothedFix(position: raw, accuracyM: acc, speedMps: 0);
    }

    var dt = (timeMs - _lastTMs) / 1000.0;
    // Duplicate timestamp or out-of-order burst: keep the last estimate.
    // Do not stretch dt up to 0.1 s — that invented speed and overshot.
    if (dt <= 0) return _last;
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
      return _last =
          SmoothedFix(position: raw, accuracyM: acc, speedMps: 0);
    }

    // Predict into locals. Commit only when the fix is accepted.
    final predE = _e + _ve * dt;
    final predN = _n + _vn * dt;
    final jump = sqrt(pow(en.e - predE, 2) + pow(en.n - predN, 2));

    // Teleport / reacquire — snap immediately.
    if (jump > max(100.0, acc * 10)) {
      _e = en.e;
      _n = en.n;
      _ve = 0;
      _vn = 0;
      _accuracy = acc;
      _holdCount = 0;
    } else if (jump > max(jumpHoldM, acc * 3) && _holdCount < jumpHoldFixes) {
      // Grace: hold the last accepted estimate. Do not integrate velocity.
      _holdCount++;
      _accuracy = 0.85 * _accuracy + 0.15 * acc;
    } else {
      _holdCount = 0;
      _e = predE;
      _n = predN;
      // Higher alpha (=k) when accuracy is good; raise further after a hold.
      var k = (1.6 / acc).clamp(0.12, 0.85);
      if (jump > jumpHoldM) k = min(0.95, k + 0.25); // catch-up
      final re = en.e - _e;
      final rn = en.n - _n;
      _e += k * re;
      _n += k * rn;
      // Denominator floor so a 50 ms burst cannot imply 100 m/s.
      final velDt = max(dt, 0.4);
      var ve = 0.7 * _ve + 0.3 * (k * re / velDt);
      var vn = 0.7 * _vn + 0.3 * (k * rn / velDt);
      final spd = sqrt(ve * ve + vn * vn);
      if (spd > maxSpeedMps) {
        final scale = maxSpeedMps / spd;
        ve *= scale;
        vn *= scale;
      }
      _ve = ve;
      _vn = vn;
      _accuracy = 0.7 * _accuracy + 0.3 * acc;
    }

    return _last = SmoothedFix(
      position: LineGeo.fromEnu(_origin!, _e, _n),
      accuracyM: _accuracy,
      speedMps: sqrt(_ve * _ve + _vn * _vn),
    );
  }

  void reset() {
    _initialized = false;
    _origin = null;
    _holdCount = 0;
    _last = null;
    _ve = 0;
    _vn = 0;
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
