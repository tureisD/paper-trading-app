import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/sync/token.dart';

void main() {
  group('sanitizeToken', () {
    test('leaves a clean token alone', () {
      const token = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
      expect(sanitizeToken(token), token);
    });

    test('removes the paste noise that causes 401 Bad credentials', () {
      expect(
        sanitizeToken('  ghp_abc123\n'),
        'ghp_abc123',
        reason: 'leading/trailing whitespace',
      );
      expect(
        sanitizeToken('ghp_ab\u00A0c123'),
        'ghp_abc123',
        reason: 'non-breaking space',
      );
      expect(
        sanitizeToken('ghp_ab\u200Bc123'),
        'ghp_abc123',
        reason: 'zero-width space',
      );
      expect(
        sanitizeToken('ghp_ab\uFEFFc123'),
        'ghp_abc123',
        reason: 'byte-order mark',
      );
      expect(
        sanitizeToken('ghp_ab\u201Cc123\u201D'),
        'ghp_abc123',
        reason: 'smart quotes from a browser',
      );
      expect(
        sanitizeToken('ghp_ab\tc\r\n123'),
        'ghp_abc123',
        reason: 'tabs and newlines',
      );
    });

    test('collapses to empty for whitespace only', () {
      expect(sanitizeToken('   \n\t\u00A0'), isEmpty);
    });

    test('keeps fine-grained token characters', () {
      const token = 'github_pat_11ABCDEFG0abcdefghijklmnopqrstuvwxyz_0123456789ABCDEF';
      expect(sanitizeToken(token), token);
    });
  });

  group('looksLikeToken', () {
    test('accepts the GitHub token prefixes', () {
      expect(looksLikeToken('ghp_abcdefghijklmnopqrstuvwx'), isTrue);
      expect(
        looksLikeToken('github_pat_11AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA_AAAAAAAAAAAAAAAAAAAAAAAAA'),
        isTrue,
      );
      expect(looksLikeToken('gho_abcdefghijklmnopqrstuvwx'), isTrue);
    });

    test('rejects junk and short values', () {
      expect(looksLikeToken(''), isFalse);
      expect(looksLikeToken('hunter2'), isFalse);
      expect(looksLikeToken('ghp_short'), isFalse);
      expect(looksLikeToken('some random pasted sentence that is long'), isFalse);
    });
  });
}
