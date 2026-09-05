import 'dart:math';

class BoundarySegment {
  final int fromCorner;
  final int toCorner;
  final double lengthMeters;

  BoundarySegment({
    required this.fromCorner,
    required this.toCorner,
    required this.lengthMeters,
  });
}

class PlotCalculationResult {
  final double areaSqMeters;
  final double areaHectares;
  final double perimeterMeters;
  final List<BoundarySegment> segments;

  PlotCalculationResult({
    required this.areaSqMeters,
    required this.areaHectares,
    required this.perimeterMeters,
    required this.segments,
  });
}

class PlotCalculator {
  /// Computes area and boundary dimensions from Lo (Y, X) coordinate pairs
  static PlotCalculationResult calculateFromLo(List<Map<String, double>> corners) {
    if (corners.length < 3) {
      return PlotCalculationResult(
        areaSqMeters: 0,
        areaHectares: 0,
        perimeterMeters: 0,
        segments: [],
      );
    }

    int n = corners.length;
    double shoelaceSum = 0.0;
    double perimeter = 0.0;
    List<BoundarySegment> segments = [];

    for (int i = 0; i < n; i++) {
      int nextIdx = (i + 1) % n;

      double y1 = corners[i]['Y']!;
      double x1 = corners[i]['X']!;
      double y2 = corners[nextIdx]['Y']!;
      double x2 = corners[nextIdx]['X']!;

      // Shoelace trapezoid formula: (Y_i * X_{i+1}) - (Y_{i+1} * X_i)
      shoelaceSum += (y1 * x2) - (y2 * x1);

      // Euclidean segment distance: sqrt(deltaY^2 + deltaX^2)
      double segmentLength = sqrt(pow(y2 - y1, 2) + pow(x2 - x1, 2));
      perimeter += segmentLength;

      segments.add(
        BoundarySegment(
          fromCorner: i + 1,
          toCorner: nextIdx + 1,
          lengthMeters: segmentLength,
        ),
      );
    }

    double areaSqM = (shoelaceSum.abs()) / 2.0;
    double areaHa = areaSqM / 10000.0; // 1 Hectare = 10,000 m²

    return PlotCalculationResult(
      areaSqMeters: areaSqM,
      areaHectares: areaHa,
      perimeterMeters: perimeter,
      segments: segments,
    );
  }
}
