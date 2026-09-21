/// Shared field-facing distance labels (guidance, pathfinder summary, etc.).
class DistanceFormat {
  DistanceFormat._();

  /// Road-vs-bush UI threshold: beyond this, emphasize Google Maps directions.
  static const double roadDirectionsThresholdM = 1500.0;

  /// ≥1 km → `121.0 km` (1 decimal); under 1 km → whole metres (`850 m`).
  /// Sub-metre approach (<10 m) keeps one decimal for bush fine guidance.
  static String format(double meters) {
    final m = meters.isFinite ? meters.abs() : 0.0;
    if (m >= 1000) {
      return '${(m / 1000).toStringAsFixed(1)} km';
    }
    if (m < 10) {
      return '${m.toStringAsFixed(1)} m';
    }
    return '${m.round()} m';
  }

  static bool preferRoadDirections(double meters) =>
      meters.isFinite && meters.abs() > roadDirectionsThresholdM;
}
