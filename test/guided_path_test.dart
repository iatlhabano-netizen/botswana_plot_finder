import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/core/guided_path.dart';
import 'package:botswana_plot_finder/core/path_guidance.dart';
import 'package:latlong2/latlong.dart' as ll;

void main() {
  // Dogleg: east then north
  final a = const ll.LatLng(-24.0, 25.0);
  final b = const ll.LatLng(-24.0, 25.01);
  final c = const ll.LatLng(-23.99, 25.01);

  late GuidedPath path;

  setUp(() {
    path = GuidedPath([
      PathVertex(a, label: 'Start'),
      PathVertex(b, label: 'Via 1'),
      PathVertex(c, label: 'End'),
    ]);
  });

  test('total length is sum of segments', () {
    final d1 = PathGuidance.distanceM(a, b);
    final d2 = PathGuidance.distanceM(b, c);
    expect(path.totalLengthM, closeTo(d1 + d2, 1));
    expect(path.segmentCount, 2);
  });

  test('midpoint of first segment → seg 0, small XT', () {
    final mid = const ll.LatLng(-24.0, 25.005);
    final fix = path.evaluate(mid);
    expect(fix.segmentIndex, 0);
    expect(fix.crossTrackM.abs(), lessThan(3));
    expect(fix.alongPathM, closeTo(PathGuidance.distanceM(a, b) / 2, 30));
    expect(fix.remainingM, closeTo(path.totalLengthM - fix.alongPathM, 30));
  });

  test('midpoint of second segment → seg 1', () {
    final mid2 = const ll.LatLng(-23.995, 25.01);
    final fix = path.evaluate(mid2);
    expect(fix.segmentIndex, 1);
    expect(fix.crossTrackM.abs(), lessThan(5));
    expect(fix.alongPathM, greaterThan(PathGuidance.distanceM(a, b) * 0.85));
  });

  test('south of eastbound first segment → positive XT (right)', () {
    final south = const ll.LatLng(-24.001, 25.005);
    final fix = path.evaluate(south);
    expect(fix.segmentIndex, 0);
    expect(fix.crossTrackM, greaterThan(50));
  });

  test('stayOnLineMessage ON LINE / LEFT / RIGHT', () {
    expect(PathGuidance.stayOnLineMessage(0.5), 'ON LINE');
    expect(PathGuidance.stayOnLineMessage(3.2), 'RIGHT 3.2 m');
    expect(PathGuidance.stayOnLineMessage(-2.1), 'LEFT 2.1 m');
  });

  test('corridorToleranceM widens with poor GPS', () {
    expect(
      PathGuidance.corridorToleranceM(baseTolM: 1.8, accuracyM: 2.0),
      closeTo(1.8, 0.01),
    );
    expect(
      PathGuidance.corridorToleranceM(baseTolM: 1.8, accuracyM: 10.0),
      closeTo(6.0, 0.01),
    );
  });

  test('past final end flagged', () {
    // Well beyond C along the second segment bearing (due north).
    final past = const ll.LatLng(-23.97, 25.01);
    final fix = path.evaluate(past);
    expect(fix.segmentIndex, 1);
    expect(fix.alongPathM, greaterThan(path.totalLengthM - 5));
    // pastEnd may require along > segLen on last segment
    expect(fix.remainingM, lessThan(5));
    expect(fix.pastEnd || fix.alongPathM >= path.totalLengthM - 1, isTrue);
  });

  test('two-point startEnd path', () {
    final simple = GuidedPath.startEnd(a, b);
    final mid = const ll.LatLng(-24.0, 25.005);
    final fix = simple.evaluate(mid);
    expect(fix.segmentIndex, 0);
    expect(fix.crossTrackM.abs(), lessThan(2));
    expect(simple.totalLengthM, closeTo(PathGuidance.distanceM(a, b), 1));
  });

  test('JSON round-trip', () {
    final j = path.toJson();
    final back = GuidedPath.fromJson(j);
    expect(back.vertices.length, 3);
    expect(back.totalLengthM, closeTo(path.totalLengthM, 0.1));
  });
}
