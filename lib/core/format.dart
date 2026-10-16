/// Minimal money formatting. Uses `$` as the display currency symbol because the
/// ledger is USD-based for now.
String formatMoney(double value, {String symbol = r'$'}) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = fixed.substring(0, dot);
  final fraction = fixed.substring(dot + 1);
  return '${negative ? '-' : ''}$symbol${_group(whole)}.$fraction';
}

String _group(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
