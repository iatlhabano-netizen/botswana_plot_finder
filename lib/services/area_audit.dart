class AreaVerificationResult {
  final double statedHectares;
  final double computedHectares;
  final double percentageDiff;
  final bool isMismatch;
  final String message;
  final double tolerancePercent;

  AreaVerificationResult({
    required this.statedHectares,
    required this.computedHectares,
    required this.percentageDiff,
    required this.isMismatch,
    required this.message,
    this.tolerancePercent = 5.0,
  });
}

class AreaAuditor {
  /// Scans OCR text for declared area (e.g., "(9.6HA)", "9,6 HA", "16,1541 hectares").
  ///
  /// A comma is a Land Board decimal (`16,154` → 16.154 ha, `16,1541` → 16.1541)
  /// unless it is a round thousands group (`1,000` / `12,000` → 1000 / 12000).
  static double? extractStatedArea(String text) {
    final regex = RegExp(
      r'(\d{1,7}(?:[.,]\d+)?)\s*(?:HA|HECTARES?|\(HA\))',
      caseSensitive: false,
    );
    final match = regex.firstMatch(text);
    if (match == null) return null;
    return _parseAreaToken(match.group(1)!);
  }

  static double? _parseAreaToken(String token) {
    if (token.contains(',') && !token.contains('.')) {
      final comma = token.indexOf(',');
      final frac = token.substring(comma + 1);
      // Only `x,000` is thousands. `16,154` is 16.154 ha, not 16 154 ha.
      final roundThousands = frac == '000';
      if (roundThousands) {
        return double.tryParse(token.replaceAll(',', ''));
      }
      return double.tryParse(token.replaceAll(',', '.'));
    }
    return double.tryParse(token);
  }

  /// Compares computed (shoelace) area against certificate declared area.
  /// Wording is "calculated vs certificate" — not "verified / survey-grade".
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
        tolerancePercent: tolerancePercent,
        message: 'No declared area on certificate to compare.',
      );
    }

    final diff =
        ((computedHectares - statedHectares).abs() / statedHectares) * 100.0;
    final mismatch = diff > tolerancePercent;

    final msg = mismatch
        ? 'Calculated ${computedHectares.toStringAsFixed(2)} Ha vs certificate '
            '${statedHectares.toStringAsFixed(2)} Ha '
            '(${diff.toStringAsFixed(1)}% apart — tolerance ±${tolerancePercent.toStringAsFixed(0)}%). '
            'Check corner order, decimals, and Lo zone.'
        : 'Calculated ${computedHectares.toStringAsFixed(2)} Ha matches certificate '
            '${statedHectares.toStringAsFixed(2)} Ha within ±${tolerancePercent.toStringAsFixed(0)}% tolerance.';

    return AreaVerificationResult(
      statedHectares: statedHectares,
      computedHectares: computedHectares,
      percentageDiff: diff,
      isMismatch: mismatch,
      tolerancePercent: tolerancePercent,
      message: msg,
    );
  }
}
