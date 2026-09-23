import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/core/path_guidance.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Control cases for geodesic path metrics.
///
/// Assumptions: spherical Earth R=6371000 m (latlong2 Distance default path
/// is also metre-based). Cross-track sign: positive = right of start→end.
void main() {
  // ~111.2 m per degree latitude
  final start = const ll.LatLng(-24.0, 25.0);
  final end = const ll.LatLng(-24.0, 25.01); // ~1 km east

  test('distance along parallel near equator-ish is ~1112 m for 0.01° lon', () {
    final d = PathGuidance.distanceM(start, end);
    // At lat -24, cos(24°)≈0.9135 → 0.01° ≈ 1015 m
    expect(d, closeTo(1015, 30));
  });

  test('bearing start→end is roughly due east (~90°)', () {
    final b = PathGuidance.bearingDeg(start, end);
    expect(b, closeTo(90, 2));
  });

  test('point on path has near-zero cross-track', () {
    final mid = const ll.LatLng(-24.0, 25.005);
    final xt = PathGuidance.crossTrackM(mid, start, end);
    expect(xt.abs(), lessThan(2.0));
  });

  test('point south of path has positive cross-track (right when facing east)', () {
    // Facing east, south is to the right → positive XT
    final south = const ll.LatLng(-24.001, 25.005);
    final xt = PathGuidance.crossTrackM(south, start, end);
    expect(xt, greaterThan(50)); // ~111 m
  });

  test('along-track at midpoint is about half the path', () {
    final mid = const ll.LatLng(-24.0, 25.005);
    final along = PathGuidance.alongTrackM(mid, start, end);
    final full = PathGuidance.distanceM(start, end);
    expect(along, closeTo(full / 2, 20));
  });

  test('arrival radius is max(3, accuracy)', () {
    expect(PathGuidance.arrivalRadiusM(null), 3.0);
    expect(PathGuidance.arrivalRadiusM(1.5), 3.0);
    expect(PathGuidance.arrivalRadiusM(8.0), 8.0);
  });

  test('true↔magnetic uses Botswana declination (~13° W)', () {
    // True north → magnetic heading ≈ 13° (compass points left of true)
    final mag = PathGuidance.trueToMagnetic(0);
    expect(mag, closeTo(13, 0.1));
    expect(PathGuidance.magneticToTrue(mag), closeTo(0, 0.1));
  });

  test('signedTurnDeg shortest path', () {
    expect(PathGuidance.signedTurnDeg(10, 30), closeTo(20, 0.01));
    expect(PathGuidance.signedTurnDeg(350, 10), closeTo(20, 0.01));
    expect(PathGuidance.signedTurnDeg(10, 350), closeTo(-20, 0.01));
  });

  test('headingAwareMessage prefers TURN when facing away', () {
    // Desired true bearing 90° → mag ≈ 103°. Heading 10° mag → large right turn.
    final msg = PathGuidance.headingAwareMessage(
      headingMagDeg: 10,
      desiredTrueBearingDeg: 90,
      xtM: 0,
    );
    expect(msg, contains('TURN RIGHT'));
  });

  test('headingAwareMessage ON PATH when aligned and on track', () {
    final desiredTrue = 90.0;
    final mag = PathGuidance.trueToMagnetic(desiredTrue);
    final msg = PathGuidance.headingAwareMessage(
      headingMagDeg: mag,
      desiredTrueBearingDeg: desiredTrue,
      xtM: 0.2,
    );
    expect(msg, 'ON PATH');
  });

  test('smoothHeading handles wrap around north', () {
    final s = PathGuidance.smoothHeading([359, 1, 0]);
    expect(s, closeTo(0, 2));
  });

  test('stayOnLineMessage ON LINE / LEFT / RIGHT', () {
    expect(PathGuidance.stayOnLineMessage(0.3), 'ON LINE');
    expect(PathGuidance.stayOnLineMessage(4.5), contains('RIGHT'));
    expect(PathGuidance.stayOnLineMessage(-1.7), contains('LEFT'));
  });

  test('corridorToleranceM expands with accuracy', () {
    expect(PathGuidance.corridorToleranceM(baseTolM: 1.8, accuracyM: 1), closeTo(1.8, 0.01));
    expect(PathGuidance.corridorToleranceM(baseTolM: 1.8, accuracyM: 5), closeTo(3.0, 0.01));
  });
}
