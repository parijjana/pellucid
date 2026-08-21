import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sidebar/widgets/safe_url.dart';

void main() {
  group('safeHttpUri', () {
    test('accepts http and https URLs', () {
      expect(safeHttpUri('https://example.com')?.toString(), 'https://example.com');
      expect(safeHttpUri('http://example.com')?.toString(), 'http://example.com');
    });

    test('normalizes a bare www. URL to https', () {
      final uri = safeHttpUri('www.example.com');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'https');
      expect(uri.toString(), 'https://www.example.com');
    });

    test('trims surrounding whitespace', () {
      final uri = safeHttpUri('  https://example.com  ');
      expect(uri?.toString(), 'https://example.com');
    });

    test('rejects file:// URLs', () {
      expect(safeHttpUri('file:///etc/passwd'), isNull);
    });

    test('rejects custom-scheme URLs', () {
      expect(safeHttpUri('javascript:alert(1)'), isNull);
      expect(safeHttpUri('myapp://do-something'), isNull);
      expect(safeHttpUri('data:text/html,hi'), isNull);
    });

    test('rejects empty or whitespace-only input', () {
      expect(safeHttpUri(''), isNull);
      expect(safeHttpUri('   '), isNull);
    });

    test('rejects unparseable input', () {
      expect(safeHttpUri('ht tp://bad uri'), isNull);
    });
  });
}
