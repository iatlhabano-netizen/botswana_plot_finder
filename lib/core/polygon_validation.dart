import 'dart:math';

/// Shared polygon sanity checks for Plot Finder + Area Calculator.
class PolygonIssue {
  final String message;
  final bool blocking;
  const PolygonIssue(this.message, {this.blocking = true});
}

class PolygonValidation {
  /// Validate Lo corner list [{Y, X}, ...].
  /// Returns all issues found (not just the first).
  static List<PolygonIssue> validateLoCorners(
    List<Map<String, double>> corners, {
    double maxSideM = 50000,
    double duplicateTolM = 0.05,
  }) {
    final issues = <PolygonIssue>[];
    if (corners.length < 3) {
      issues.add(const PolygonIssue('Need at least 3 corners for a polygon.'));
      return issues;
    }

    final bad = <int>[];
    for (var i = 0; i < corners.length; i++) {
      final y = corners[i]['Y'];
      final x = corners[i]['X'];
      if (y == null || x == null || y.isNaN || x.isNaN) {
        bad.add(i + 1);
      }
    }
    if (bad.isNotEmpty) {
      issues.add(PolygonIssue(
        'Invalid Y/X at corner(s): ${bad.join(", ")}.',
      ));
    }

    // Duplicates
    for (var i = 0; i < corners.length; i++) {
      for (var j = i + 1; j < corners.length; j++) {
        final dy = (corners[i]['Y']! - corners[j]['Y']!).abs();
        final dx = (corners[i]['X']! - corners[j]['X']!).abs();
        if (sqrt(dy * dy + dx * dx) <= duplicateTolM) {
          issues.add(PolygonIssue(
            'Corners ${i + 1} and ${j + 1} are duplicates (same point).',
          ));
        }
      }
    }

    // Zero / wild sides
    final n = corners.length;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final dy = corners[j]['Y']! - corners[i]['Y']!;
      final dx = corners[j]['X']! - corners[i]['X']!;
      final len = sqrt(dy * dy + dx * dx);
      if (len < duplicateTolM) {
        issues.add(PolygonIssue(
          'Zero-length side between C${i + 1} and C${j + 1}.',
        ));
      } else if (len > maxSideM) {
        issues.add(PolygonIssue(
          'Unusually long side C${i + 1}→C${j + 1}: ${(len / 1000).toStringAsFixed(1)} km — check order/zone.',
          blocking: false,
        ));
      }
    }

    if (_selfIntersects(corners)) {
      issues.add(const PolygonIssue(
        'Polygon edges cross (self-intersection). Check corner order — walk the boundary clockwise or counter-clockwise without crossing.',
        blocking: false,
      ));
    }

    return issues;
  }

  static bool _selfIntersects(List<Map<String, double>> c) {
    final n = c.length;
    if (n < 4) return false;
    for (var i = 0; i < n; i++) {
      final a1 = c[i];
      final a2 = c[(i + 1) % n];
      for (var j = i + 1; j < n; j++) {
        // Skip adjacent edges and the closing edge pair that share a vertex
        if ((j + 1) % n == i) continue;
        if (j == (i + 1) % n) continue;
        final b1 = c[j];
        final b2 = c[(j + 1) % n];
        if (_segmentsCross(
          a1['Y']!, a1['X']!, a2['Y']!, a2['X']!,
          b1['Y']!, b1['X']!, b2['Y']!, b2['X']!,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  /// Proper segment intersection (excluding shared endpoints).
  static bool _segmentsCross(
    double ax, double ay, double bx, double by,
    double cx, double cy, double dx, double dy,
  ) {
    final d1 = _orient(ax, ay, bx, by, cx, cy);
    final d2 = _orient(ax, ay, bx, by, dx, dy);
    final d3 = _orient(cx, cy, dx, dy, ax, ay);
    final d4 = _orient(cx, cy, dx, dy, bx, by);
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    return false;
  }

  static double _orient(
      double ax, double ay, double bx, double by, double cx, double cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }
}
