import 'dart:math';
import 'package:latlong2/latlong.dart' as ll;

/// Geodesic path metrics for open-bush line following (cross-track / along-track).
class PathGuidance {
  static const double earthRadiusM = 6371000.0;
  static const ll.Distance _d = ll.Distance();

  /// Approximate magnetic declination for Botswana / eastern SADC (west = negative).
  /// Mean ~13° W — compass headings are magnetic; path bearings are true.
  static const double botswanaDeclinationDeg = -13.0;

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

  /// True bearing degrees (geographic north).
  static double bearingDeg(ll.LatLng a, ll.LatLng b) =>
      (_brg(a, b) * 180 / pi + 360) % 360;

  /// Convert true bearing → magnetic for compass UI (Botswana ~13° W).
  static double trueToMagnetic(double trueDeg,
          {double declinationDeg = botswanaDeclinationDeg}) =>
      (trueDeg - declinationDeg + 360) % 360;

  /// Convert magnetic heading → true.
  static double magneticToTrue(double magDeg,
          {double declinationDeg = botswanaDeclinationDeg}) =>
      (magDeg + declinationDeg + 360) % 360;

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

  /// Arrival radius: at least 3 m, and never tighter than GPS accuracy.
  static double arrivalRadiusM(double? accuracyM) =>
      max(3.0, accuracyM ?? 3.0);

  /// Human-readable CTE guidance assuming walker faces along the path.
  static String crossTrackMessage(double xtM, {double onTrackTolM = 1.5}) {
    if (xtM.abs() <= onTrackTolM) return 'ON PATH';
    if (xtM > 0) return 'VEER LEFT ${xtM.abs().toStringAsFixed(1)} m';
    return 'VEER RIGHT ${xtM.abs().toStringAsFixed(1)} m';
  }

  /// Heading-aware turn advice: uses device magnetic heading vs desired
  /// magnetic bearing to the target (or along-path correction).
  ///
  /// [headingMagDeg] = compass heading (magnetic).
  /// [desiredTrueBearingDeg] = true bearing toward target / along path.
  /// [xtM] = cross-track (positive = right of path); null in locate mode.
  static String headingAwareMessage({
    required double headingMagDeg,
    required double desiredTrueBearingDeg,
    double? xtM,
    double onTrackTolM = 1.5,
    double declinationDeg = botswanaDeclinationDeg,
  }) {
    final desiredMag =
        trueToMagnetic(desiredTrueBearingDeg, declinationDeg: declinationDeg);
    final turn = signedTurnDeg(headingMagDeg, desiredMag);

    if (xtM != null && xtM.abs() <= onTrackTolM && turn.abs() <= 15) {
      return 'ON PATH';
    }

    // Large heading error dominates when facing away from the path/target.
    if (turn.abs() > 35) {
      if (turn > 0) {
        return 'TURN RIGHT ${turn.abs().toStringAsFixed(0)}°';
      }
      return 'TURN LEFT ${turn.abs().toStringAsFixed(0)}°';
    }

    if (xtM != null && xtM.abs() > onTrackTolM) {
      return crossTrackMessage(xtM, onTrackTolM: onTrackTolM);
    }

    if (turn.abs() > 8) {
      if (turn > 0) {
        return 'BEAR RIGHT ${turn.abs().toStringAsFixed(0)}°';
      }
      return 'BEAR LEFT ${turn.abs().toStringAsFixed(0)}°';
    }
    return 'ON PATH';
  }

  /// Signed smallest turn from [fromDeg] to [toDeg]: positive = turn right.
  static double signedTurnDeg(double fromDeg, double toDeg) {
    var d = (toDeg - fromDeg) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Low-pass / median smooth of recent magnetic headings (circular).
  static double smoothHeading(List<double> recent, {double? alpha}) {
    if (recent.isEmpty) return 0;
    if (recent.length == 1) return recent.first;
    // Convert to unit vectors and average (handles 359/1 wrap).
    double sx = 0, sy = 0;
    for (final h in recent) {
      final r = h * pi / 180;
      sx += cos(r);
      sy += sin(r);
    }
    return (atan2(sy / recent.length, sx / recent.length) * 180 / pi + 360) %
        360;
  }
}

/// Alias kept for any leftover references.
typedef BushNavigator = PathGuidance;
