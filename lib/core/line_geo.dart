import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

/// Farm-scale geodesy helpers for stay-on-line guidance.
///
/// **Sign convention:** signed cross-track is **positive = RIGHT** of the
/// directed travel a→b (eastbound: south = +, north = −).
class LineGeo {
  LineGeo._();

  static const double earthRadiusM = 6371000.0;
  static const double _deg = pi / 180;
  static const double _latScale = 111320.0; // m per degree latitude

  static double distanceM(ll.LatLng a, ll.LatLng b) {
    final dLat = (b.latitude - a.latitude) * _deg;
    final dLon = (b.longitude - a.longitude) * _deg;
    final s1 = sin(dLat / 2);
    final s2 = sin(dLon / 2);
    final h = s1 * s1 +
        cos(a.latitude * _deg) * cos(b.latitude * _deg) * s2 * s2;
    return 2 * earthRadiusM * asin(min(1.0, sqrt(h)));
  }

  /// Initial bearing a→b, degrees 0–360 clockwise from north.
  static double bearingDeg(ll.LatLng a, ll.LatLng b) {
    final la1 = a.latitude * _deg;
    final la2 = b.latitude * _deg;
    final dLon = (b.longitude - a.longitude) * _deg;
    final y = sin(dLon) * cos(la2);
    final x =
        cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon);
    return (atan2(y, x) / _deg + 360) % 360;
  }

  /// Destination from [p] along [brgDeg] for [distM] metres.
  static ll.LatLng destination(ll.LatLng p, double brgDeg, double distM) {
    final d = distM / earthRadiusM;
    final brg = brgDeg * _deg;
    final la1 = p.latitude * _deg;
    final lo1 = p.longitude * _deg;
    final la2 = asin(
      sin(la1) * cos(d) + cos(la1) * sin(d) * cos(brg),
    );
    final lo2 = lo1 +
        atan2(
          sin(brg) * sin(d) * cos(la1),
          cos(d) - sin(la1) * sin(la2),
        );
    return ll.LatLng(la2 / _deg, ((lo2 / _deg) + 540) % 360 - 180);
  }

  /// Spherical signed cross-track (m). Positive = RIGHT of a→b.
  static double crossTrackM(ll.LatLng p, ll.LatLng a, ll.LatLng b) {
    final d13 = distanceM(a, p) / earthRadiusM;
    final t13 = bearingDeg(a, p) * _deg;
    final t12 = bearingDeg(a, b) * _deg;
    final s = (sin(d13) * sin(t13 - t12)).clamp(-1.0, 1.0);
    return asin(s) * earthRadiusM;
  }

  /// Local ENU metres relative to [origin] (east, north).
  static ({double e, double n}) toEnu(ll.LatLng origin, ll.LatLng p) {
    final lonScale = _latScale * cos(origin.latitude * _deg);
    return (
      e: (p.longitude - origin.longitude) * lonScale,
      n: (p.latitude - origin.latitude) * _latScale,
    );
  }

  static ll.LatLng fromEnu(ll.LatLng origin, double e, double n) {
    final lonScale = _latScale * cos(origin.latitude * _deg);
    return ll.LatLng(
      origin.latitude + n / _latScale,
      origin.longitude + e / lonScale,
    );
  }
}

/// Finite-segment projection in a local ENU frame.
class SegProjection {
  /// Unclamped parameter along segment (0 at a, 1 at b).
  final double t;

  /// Clamped to [0, 1].
  final double tClamped;

  /// Signed lateral offset (m): **positive = RIGHT** of a→b.
  final double lateralM;

  final double lengthM;

  /// Distance from point to clamped foot (m).
  final double distToSegM;

  final bool interior;

  const SegProjection({
    required this.t,
    required this.tClamped,
    required this.lateralM,
    required this.lengthM,
    required this.distToSegM,
    required this.interior,
  });
}

/// Project [p] onto segment a→b in ENU about [origin].
///
/// Cross product uses RIGHT-positive convention (eastbound south = +).
SegProjection projectSegmentEnu({
  required ll.LatLng origin,
  required ll.LatLng p,
  required ll.LatLng a,
  required ll.LatLng b,
}) {
  final pa = LineGeo.toEnu(origin, a);
  final pb = LineGeo.toEnu(origin, b);
  final pp = LineGeo.toEnu(origin, p);
  final abx = pb.e - pa.e;
  final aby = pb.n - pa.n;
  final len = sqrt(abx * abx + aby * aby);
  if (len < 1e-9) {
    final dx = pp.e - pa.e;
    final dy = pp.n - pa.n;
    return SegProjection(
      t: 0,
      tClamped: 0,
      lateralM: 0,
      lengthM: 0,
      distToSegM: sqrt(dx * dx + dy * dy),
      interior: false,
    );
  }
  final apx = pp.e - pa.e;
  final apy = pp.n - pa.n;
  final t = (apx * abx + apy * aby) / (len * len);
  // RIGHT-positive: (aby*apx - abx*apy)/len  (eastbound, south → +)
  final lateral = (aby * apx - abx * apy) / len;
  final tc = t.clamp(0.0, 1.0);
  final fx = pa.e + tc * abx;
  final fy = pa.n + tc * aby;
  final dx = pp.e - fx;
  final dy = pp.n - fy;
  return SegProjection(
    t: t,
    tClamped: tc,
    lateralM: lateral,
    lengthM: len,
    distToSegM: sqrt(dx * dx + dy * dy),
    interior: t > 0 && t < 1,
  );
}
