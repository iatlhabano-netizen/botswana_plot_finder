import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/services/plot_calculator.dart';
import 'package:botswana_plot_finder/core/polygon_validation.dart';
import 'package:botswana_plot_finder/core/lo_format.dart';

/// Shoelace golden for the Sample Lo rectangle.
///
/// Sample corners (Lo metres):
///   C1 (-74283, 2609149)
///   C2 (-74593, 2609153)
///   C3 (-74589, 2609473)
///   C4 (-74279, 2609469)
///
/// Approximate width ≈ 310 m, height ≈ 320 m → area ≈ 9.9 Ha.
/// Exact shoelace is the control — do not "fix" by eye.
void main() {
  final sample = [
    {'Y': -74283.0, 'X': 2609149.0},
    {'Y': -74593.0, 'X': 2609153.0},
    {'Y': -74589.0, 'X': 2609473.0},
    {'Y': -74279.0, 'X': 2609469.0},
  ];

  test('sample plot shoelace area is ~9.9 Ha', () {
    final r = PlotCalculator.calculateFromLo(sample);
    // Documented control from prior releases / hand check
    expect(r.areaHectares, closeTo(9.92, 0.15));
    expect(r.areaSqMeters, closeTo(r.areaHectares * 10000, 1.0));
    expect(r.segments.length, 4);
    expect(r.perimeterMeters, greaterThan(1000));
    expect(r.perimeterMeters, lessThan(1500));
  });

  test('unit square 100×100 m = 1 Ha', () {
    final sq = [
      {'Y': 0.0, 'X': 0.0},
      {'Y': 100.0, 'X': 0.0},
      {'Y': 100.0, 'X': 100.0},
      {'Y': 0.0, 'X': 100.0},
    ];
    final r = PlotCalculator.calculateFromLo(sq);
    expect(r.areaHectares, closeTo(1.0, 1e-9));
    expect(r.perimeterMeters, closeTo(400.0, 1e-9));
  });

  test('fewer than 3 corners → zero area', () {
    final r = PlotCalculator.calculateFromLo([
      {'Y': 0.0, 'X': 0.0},
      {'Y': 1.0, 'X': 1.0},
    ]);
    expect(r.areaHectares, 0);
  });

  test('polygon validation catches duplicates and self-intersection', () {
    final dup = [
      {'Y': 0.0, 'X': 0.0},
      {'Y': 100.0, 'X': 0.0},
      {'Y': 0.0, 'X': 0.0}, // duplicate of C1
    ];
    final issues = PolygonValidation.validateLoCorners(dup);
    expect(issues.any((i) => i.message.contains('duplicate')), isTrue);

    // Bow-tie
    final bow = [
      {'Y': 0.0, 'X': 0.0},
      {'Y': 100.0, 'X': 100.0},
      {'Y': 100.0, 'X': 0.0},
      {'Y': 0.0, 'X': 100.0},
    ];
    final bowIssues = PolygonValidation.validateLoCorners(bow);
    expect(
      bowIssues.any((i) => i.message.toLowerCase().contains('cross')),
      isTrue,
    );
  });

  test('formatLoCoord keeps decimals when present', () {
    expect(formatLoCoord(-74283.0), '-74283');
    expect(formatLoCoord(-74283.25), '-74283.25');
    expect(formatLoCoord(2609149.5), '2609149.5');
    expect(formatLoCoord(2609149.125), '2609149.125');
  });
}
