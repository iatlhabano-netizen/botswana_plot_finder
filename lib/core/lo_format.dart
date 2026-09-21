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
