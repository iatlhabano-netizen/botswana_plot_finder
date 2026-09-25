/// Format Lo westing/southing for forms and OCR fill.
/// Keeps 2–3 decimal places when present on the certificate; strips trailing zeros.
String formatLoCoord(double value, {int maxDecimals = 3}) {
  if (value.isNaN || value.isInfinite) return '';
  if ((value - value.roundToDouble()).abs() < 1e-9) {
    return value.round().toString();
  }
  var s = value.toStringAsFixed(maxDecimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Collapse OCR / certificate artifacts in Lo numbers.
///
/// Handles spaced signs, EU comma decimals, space or dot thousands, and
/// US comma thousands. Leaves bearings like `1.20.43` alone.
///
/// Examples: `- 255 124.38` → `-255124.38`, `+103 208,35` → `+103208.35`,
/// `+2.702.523,47` → `+2702523.47`, `255,124.38` → `255124.38`.
String normalizeLoNumberText(String text) {
  var s = text;
  // Spaced sign before a digit: "- 255" / "+ 7" → "-255" / "+7"
  s = s.replaceAllMapped(RegExp(r'([+-])\s+(?=\d)'), (m) => m.group(1)!);

  // Dot thousands + comma decimal (OCR of EU grouping): 2.702.523,47
  s = s.replaceAllMapped(
    RegExp(r'(?<![\d])\d{1,3}(?:\.\d{3})+,\d{1,2}(?!\d)'),
    (m) => m.group(0)!.replaceAll('.', '').replaceAll(',', '.'),
  );

  // European / Land Board: spaced thousands + comma decimals
  // e.g. 103 208,35 / 2 702 523,47 → 103208.35 / 2702523.47
  s = s.replaceAllMapped(
    RegExp(r'(?<![\d.])\d{1,3}(?:\s\d{3})+,\d{1,3}(?!\d)'),
    (m) => m.group(0)!.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'),
  );

  // European unspaced with 1–2 decimal digits (avoid ,ddd US thousands):
  // 103208,35 → 103208.35
  s = s.replaceAllMapped(
    RegExp(r'(?<![\d.])\d{4,12},\d{1,2}(?!\d)'),
    (m) => m.group(0)!.replaceAll(',', '.'),
  );

  // US/OCR thousands commas: 255,124.38 or 2,609,149
  s = s.replaceAllMapped(
    RegExp(r'(?<![\d.])\d{1,3}(?:,\d{3})+(?:\.\d+)?'),
    (m) => m.group(0)!.replaceAll(',', ''),
  );

  // Spaced thousands groups: 255 124.38 / 7 604 978.00
  s = s.replaceAllMapped(
    RegExp(r'(?<![\d.])\d{1,3}(?:\s\d{3})+(?:\.\d+)?'),
    (m) => m.group(0)!.replaceAll(RegExp(r'\s'), ''),
  );

  return s;
}

/// Parse one Lo field typed or pasted by the user (`103 208,35`, `+2702523.47`).
double? tryParseLoNumber(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final normalized = normalizeLoNumberText(trimmed).replaceAll(RegExp(r'\s'), '');
  return double.tryParse(normalized);
}
