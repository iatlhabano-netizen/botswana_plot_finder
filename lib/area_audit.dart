class AreaVerificationResult {
  final double statedHectares;
  final double computedHectares;
  final double percentageDiff;
  final bool isMismatch;
  final String message;

  AreaVerificationResult({
    required this.statedHectares,
    required this.computedHectares,
    required this.percentageDiff,
    required this.isMismatch,
    required this.message,
  });
}

class AreaAuditor {
  /// Scans OCR text for declared area (e.g., "(9.6HA)" or "9.6 HA" or "9.6HECTARES")
  static double? extractStatedArea(String text) {
    final regex = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:HA|HECTARES?|\(HA\))',
      caseSensitive: false,
    );
    final match = regex.firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Compares computed area against stated area
  static AreaVerificationResult auditArea({
    required double computedHectares,
    required double statedHectares,
    double tolerancePercent = 5.0,
  }) {
    if (statedHectares <= 0) {
      return AreaVerificationResult(
        statedHectares: 0,
        computedHectares: computedHectares,
        percentageDiff: 0,
        isMismatch: false,
        message: 'No declared area specified on certificate.',
      );
    }

    double diff = ((computedHectares - statedHectares).abs() / statedHectares) * 100.0;
    bool mismatch = diff > tolerancePercent;

    String msg = mismatch
        ? 'Warning: Computed area (${computedHectares.toStringAsFixed(2)} Ha) differs from certificate (${statedHectares.toStringAsFixed(2)} Ha) by ${diff.toStringAsFixed(1)}%.'
        : 'Area verified: Computed area matches stated certificate area within normal survey tolerance.';

    return AreaVerificationResult(
      statedHectares: statedHectares,
      computedHectares: computedHectares,
      percentageDiff: diff,
      isMismatch: mismatch,
      message: msg,
    );
  }
}
