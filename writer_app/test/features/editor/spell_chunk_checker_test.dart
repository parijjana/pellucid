// Description: chunked spell check: paragraph splitting, per-paragraph cache, offset remap, and equality
// with a whole-text check (so macOS callers get the same spans).

import 'package:flutter/services.dart' show SuggestionSpan;
import 'package:flutter/widgets.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/services/spell_chunk_checker.dart';

/// Flags words in [bad]; counts calls and the characters it was asked to check.
class Fake {
  final Set<String> bad;
  final calls = <String>[];
  Fake(this.bad);

  List<SuggestionSpan> run(String text) {
    calls.add(text);
    final out = <SuggestionSpan>[];
    for (final m in RegExp(r'[^\s]+').allMatches(text)) {
      if (bad.contains(m.group(0))) out.add(SuggestionSpan(TextRange(start: m.start, end: m.end), [m.group(0)!.toUpperCase()]));
    }
    return out;
  }

  Future<List<SuggestionSpan>?> call(String t) async => run(t);
}

List<String> show(List<SuggestionSpan> s) => [for (final x in s) '${x.range.start}-${x.range.end}'];

void main() {
  group('splitSpellUnits', () {
    test('paragraphs, blank lines skipped, offsets absolute', () {
      const t = 'one two\n\nthree\n  \nfour';
      final u = splitSpellUnits(t);
      expect([for (final x in u) t.substring(x.start, x.end)], ['one two', 'three', 'four']);
    });

    test('CRLF: carriage return stays at the end of its piece, offsets unchanged', () {
      const t = 'aa bb\r\n\r\ncc dd\r\n';
      final u = splitSpellUnits(t);
      expect([for (final x in u) t.substring(x.start, x.end)], ['aa bb\r', 'cc dd\r']);
      expect(u[1].start, t.indexOf('cc'));
    });

    test('long paragraph is cut at whitespace, pieces cover it without gaps', () {
      final t = List.generate(500, (i) => 'word$i').join(' ');
      final u = splitSpellUnits(t, maxChars: 100);
      expect(u.length, greaterThan(5));
      for (final x in u) {
        expect(x.length, lessThanOrEqualTo(100));
        expect(t.substring(x.start, x.end).startsWith(' ') || x.start == 0 || t[x.start - 1] == ' ', isTrue);
      }
      // No word is cut: every piece ends at a word end.
      for (final x in u.take(u.length - 1)) {
        expect(t[x.end - 1] == ' ' || t[x.end] == ' ', isTrue);
      }
      expect(u.last.end, t.length);
    });

    test('long run without whitespace is hard cut but never between surrogates', () {
      final t = '😀' * 100; // 200 UTF-16 units, no spaces
      final u = splitSpellUnits(t, maxChars: 51);
      for (final x in u) {
        expect(x.length.isEven, isTrue, reason: 'no half emoji');
      }
      expect(u.fold<int>(0, (a, x) => a + x.length), 200);
    });
  });

  group('SpellChunkChecker', () {
    const base = 'The cat sat\nteh dog ran\n\nA quiet teh paragraph\nlast one';

    test('equals the whole-text check (offsets and suggestions)', () async {
      final f = Fake({'teh'});
      final c = SpellChunkChecker(f.call, maxChars: 20);
      final got = await c.check(base);
      final want = Fake({'teh'}).run(base);
      expect(show(got!), show(want));
      expect([for (final s in got) s.suggestions], [for (final s in want) s.suggestions]);
    });

    test('no edit: second check asks the checker nothing', () async {
      final f = Fake({'teh'});
      final c = SpellChunkChecker(f.call, maxChars: 20);
      await c.check(base);
      final n = f.calls.length;
      final again = await c.check(base);
      expect(f.calls.length, n);
      expect(c.callsLastCheck, 0);
      expect(show(again!), show(Fake({'teh'}).run(base)));
    });

    test('edit inside one paragraph re-checks only that paragraph; offsets after it shift', () async {
      final f = Fake({'teh'});
      final c = SpellChunkChecker(f.call, maxChars: 20);
      await c.check(base);
      f.calls.clear();
      final edited = base.replaceFirst('dog ran', 'dog ran fast teh');
      final got = await c.check(edited);
      expect(f.calls.join('|').contains('last one') && f.calls.length > 2, isFalse, reason: 'later paragraphs came from the cache');
      expect(show(got!), show(Fake({'teh'}).run(edited)));
      expect(f.calls.every((t) => t.length <= 20), isTrue);
    });

    test('edit before everything shifts cached spans without asking again', () async {
      final f = Fake({'teh'});
      final c = SpellChunkChecker(f.call, maxChars: 20);
      await c.check(base);
      f.calls.clear();
      final edited = 'Prologue line\n$base';
      final got = await c.check(edited);
      expect(f.calls, ['Prologue line']);
      expect(show(got!), show(Fake({'teh'}).run(edited)));
    });

    test('edit after everything leaves earlier pieces cached', () async {
      final f = Fake({'teh'});
      final c = SpellChunkChecker(f.call, maxChars: 20);
      await c.check(base);
      f.calls.clear();
      final edited = '$base teh';
      final got = await c.check(edited);
      expect(f.calls, ['last one teh']);
      expect(show(got!), show(Fake({'teh'}).run(edited)));
    });

    test('paragraph inserted and deleted', () async {
      final f = Fake({'teh'});
      final c = SpellChunkChecker(f.call, maxChars: 20);
      await c.check(base);
      f.calls.clear();
      final inserted = base.replaceFirst('\n\n', '\n\nbrand teh new\n\n');
      expect(show((await c.check(inserted))!), show(Fake({'teh'}).run(inserted)));
      expect(f.calls, ['brand teh new']);
      final deleted = base.replaceFirst('teh dog ran\n', '');
      expect(show((await c.check(deleted))!), show(Fake({'teh'}).run(deleted)));
    });

    test('CRLF document gives the same spans as a whole-text check', () async {
      final t = base.replaceAll('\n', '\r\n');
      final c = SpellChunkChecker(Fake({'teh'}).call, maxChars: 20);
      expect(show((await c.check(t))!), show(Fake({'teh'}).run(t)));
    });

    test('emoji and surrogates before a misspelling keep offsets right', () async {
      const t = 'Hi 😀😀 there\n😀 teh end 👩‍👩‍👧 teh\nplain teh';
      final c = SpellChunkChecker(Fake({'teh'}).call, maxChars: 24);
      final got = await c.check(t);
      expect(show(got!), show(Fake({'teh'}).run(t)));
      for (final s in got) {
        expect(t.substring(s.range.start, s.range.end), 'teh');
      }
    });

    test('long paragraph split in pieces: spans equal the whole-text check', () async {
      final t = List.generate(300, (i) => i % 17 == 0 ? 'teh' : 'ok$i').join(' ');
      final c = SpellChunkChecker(Fake({'teh'}).call, maxChars: 120);
      expect(show((await c.check(t))!), show(Fake({'teh'}).run(t)));
      expect(c.callsLastCheck, greaterThan(5));
    });

    test('every call is at most maxChars long', () async {
      final f = Fake({'teh'});
      final t = List.generate(400, (i) => 'para $i teh and more words').join('\n\n');
      final c = SpellChunkChecker(f.call, maxChars: 200);
      await c.check(t);
      expect(f.calls.every((x) => x.length <= 200), isTrue);
    });

    test('clear() forces a fresh check', () async {
      final f = Fake({'teh'});
      final c = SpellChunkChecker(f.call, maxChars: 20);
      await c.check(base);
      c.clear();
      f.calls.clear();
      await c.check(base);
      expect(f.calls, isNotEmpty);
    });

    test('cancel stops the work, keeps what was done, next check resumes', () async {
      final f = Fake({'teh'});
      final t = List.generate(40, (i) => 'paragraph number $i teh').join('\n');
      final c = SpellChunkChecker(f.call, maxChars: 60);
      int n = 0;
      final r = await c.check(t, cancelled: () => ++n > 6);
      expect(r, isNull);
      final done = f.calls.length;
      expect(done, greaterThan(0));
      f.calls.clear();
      final full = await c.check(t);
      expect(show(full!), show(Fake({'teh'}).run(t)));
      expect(f.calls.length, lessThan(done + 40));
      expect(f.calls.any((x) => x.startsWith('paragraph number 0 ')), isFalse, reason: 'early pieces were cached');
    });

    test('null answer from the service means no spans, not a crash', () async {
      final c = SpellChunkChecker((t) async => null);
      expect(await c.check(base), isEmpty);
    });
  });
}
