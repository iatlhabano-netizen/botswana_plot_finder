import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/core/distance_format.dart';

void main() {
  test('formats long distances in km with 1 decimal', () {
    expect(DistanceFormat.format(121006), '121.0 km');
    expect(DistanceFormat.format(121169), '121.2 km');
    expect(DistanceFormat.format(1500), '1.5 km');
    expect(DistanceFormat.format(1000), '1.0 km');
  });

  test('formats under 1 km as whole metres', () {
    expect(DistanceFormat.format(850), '850 m');
    expect(DistanceFormat.format(999.4), '999 m');
    expect(DistanceFormat.format(10), '10 m');
  });

  test('formats sub-10 m with one decimal', () {
    expect(DistanceFormat.format(9.6), '9.6 m');
    expect(DistanceFormat.format(0.4), '0.4 m');
  });

  test('road directions threshold is 1500 m', () {
    expect(DistanceFormat.roadDirectionsThresholdM, 1500);
    expect(DistanceFormat.preferRoadDirections(1500.1), isTrue);
    expect(DistanceFormat.preferRoadDirections(1500), isFalse);
    expect(DistanceFormat.preferRoadDirections(200), isFalse);
  });
}
