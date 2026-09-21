import 'dart:math';
import 'package:latlong2/latlong.dart' as ll;

/// Geodesic path metrics for open-bush line following (cross-track / along-track).
class PathGuidance {
  static const double earthRadiusM = 6371000.0;
  static const ll.Distance _d = ll.Distance();

  static double distanceM(ll.LatLng a, ll.LatLng b) =>
      _d.as(ll.LengthUnit.Meter, a, b);

  static double _brg(ll.LatLng a, ll.LatLng b) {
    final la = a.latitude * pi / 180;
    final lb = b.latitude * pi / 180;
    final dl = (b.longitude - a.longitude) * pi / 180;
    return atan2(
      sin(dl) * cos(lb),
      cos(la) * sin(lb) - sin(la) * cos(lb) * cos(dl),
    );
  }

  static double bearingDeg(ll.LatLng a, ll.LatLng b) =>
      (_brg(a, b) * 180 / pi + 360) % 360;

  /// Positive = right of path (looking start→end); negative = left.
  static double crossTrackM(ll.LatLng cur, ll.LatLng start, ll.LatLng end) {
    final d13 = distanceM(start, cur) / earthRadiusM;
    return asin(sin(d13) * sin(_brg(start, cur) - _brg(start, end))) *
        earthRadiusM;
  }

  /// Signed along-track from start toward end. Negative = behind start.
  static double alongTrackM(ll.LatLng cur, ll.LatLng start, ll.LatLng end) {
    final d13 = distanceM(start, cur) / earthRadiusM;
    final d12 = distanceM(start, end) / earthRadiusM;
    final t = _brg(start, cur) - _brg(start, end);
    final cosA =
        (cos(d13) * cos(d12) + sin(d13) * sin(d12) * cos(t)).clamp(-1.0, 1.0);
    final mag = acos(cosA) * earthRadiusM;
    return cos(t) >= 0 ? mag : -mag;
  }

  static bool isPastEnd(ll.LatLng cur, ll.LatLng start, ll.LatLng end) {
    return alongTrackM(cur, start, end) > distanceM(start, end);
  }

  /// Human-readable CTE guidance for outdoor UI.
  static String crossTrackMessage(double xtM, {double onTrackTolM = 1.5}) {
    if (xtM.abs() <= onTrackTolM) return 'ON PATH';
    if (xtM > 0) return 'VEER LEFT ${xtM.abs().toStringAsFixed(1)} m';
    return 'VEER RIGHT ${xtM.abs().toStringAsFixed(1)} m';
  }
}

/// Alias kept for any leftover references.
typedef BushNavigator = PathGuidance;
