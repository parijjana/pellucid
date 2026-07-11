import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/search/providers/text_replacer.dart';

RegExp _searchPattern(String query) => RegExp(RegExp.escape(query), caseSensitive: false);

void main() {
  group('replaceAll', () {
    test('empty query is a no-op (mirrors search short-circuit)', () {
      final result = replaceAll('Hello world', _searchPattern(''), 'X');
      expect(result.text, 'Hello world');
      expect(result.count, 0);
    });

    test('no-match query is a no-op', () {
      final result = replaceAll('Hello world', _searchPattern('zzz'), 'X');
      expect(result.text, 'Hello world');
      expect(result.count, 0);
    });

    test('case-insensitive substring replaces every occurrence', () {
      final result = replaceAll('Cat cat CAT catapult', _searchPattern('cat'), 'dog');
      expect(result.text, 'dog dog dog dogapult');
      expect(result.count, 4);
    });

    test('overlapping candidates resolve left-to-right non-overlapping, like search', () {
      // "aa" against "aaaa" -> two non-overlapping matches at [0,2) and [2,4),
      // matching RegExp.allMatches semantics used by SearchProvider.
      final result = replaceAll('aaaa', _searchPattern('aa'), 'b');
      expect(result.text, 'bb');
      expect(result.count, 2);
    });

    test('unicode: em-dash and accented characters replace correctly', () {
      final result = replaceAll('Café—the roast', _searchPattern('café'), 'Bistro');
      expect(result.text, 'Bistro—the roast');
      expect(result.count, 1);
    });

    test('skipRange excludes overlapping matches (e.g. Attributions region)', () {
      const source = 'cat sees cat, # Attributions\ncat wrote this\n# The End\ncat again';
      final attributionsStart = source.indexOf('# Attributions');
      final attributionsEnd = source.indexOf('# The End');

      final result = replaceAll(
        source,
        _searchPattern('cat'),
        'dog',
        skipRangeStart: attributionsStart,
        skipRangeEnd: attributionsEnd,
      );

      // Two occurrences before the region and one after are replaced; the one
      // inside [attributionsStart, attributionsEnd) is left untouched.
      expect(result.count, 3);
      expect(result.text, 'dog sees dog, # Attributions\ncat wrote this\n# The End\ndog again');
    });
  });

  group('replaceOne', () {
    test('empty query is a no-op', () {
      final result = replaceOne('Hello world', _searchPattern(''), 'X', 0);
      expect(result.text, 'Hello world');
      expect(result.count, 0);
    });

    test('replaces only the match starting at matchStart', () {
      const source = 'cat cat cat';
      final result = replaceOne(source, _searchPattern('cat'), 'dog', 4);
      expect(result.text, 'cat dog cat');
      expect(result.count, 1);
    });

    test('returns source unchanged (count 0) when nothing starts at matchStart', () {
      const source = 'cat cat cat';
      final result = replaceOne(source, _searchPattern('cat'), 'dog', 1);
      expect(result.text, source);
      expect(result.count, 0);
    });
  });
}
