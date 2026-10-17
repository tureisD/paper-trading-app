/// Token hygiene.
///
/// Copy-paste is the usual culprit behind a `401 Bad credentials`: a trailing
/// newline, a non-breaking space, a zero-width character, or a smart quote that
/// travelled with the token out of a browser or password manager. GitHub tokens
/// are ASCII with no whitespace, so anything else is stripped rather than sent.
String sanitizeToken(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    // Control characters, every Unicode space, and zero-width joiners/marks.
    if (rune <= 0x20) continue;
    if (rune == 0x7F || rune == 0xAD) continue;
    if (rune >= 0xA0 && rune <= 0x200F) continue;
    if (rune == 0x2028 || rune == 0x2029 || rune == 0xFEFF) continue;
    // Tokens never contain non-ASCII; anything else is paste noise.
    if (rune > 0x7E) continue;
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// True when the value looks like a GitHub token we can send.
bool looksLikeToken(String value) {
  final token = sanitizeToken(value);
  if (token.length < 20) return false;
  return token.startsWith('ghp_') ||
      token.startsWith('github_pat_') ||
      token.startsWith('gho_') ||
      token.startsWith('ghu_') ||
      token.startsWith('ghs_') ||
      token.startsWith('ghr_');
}
