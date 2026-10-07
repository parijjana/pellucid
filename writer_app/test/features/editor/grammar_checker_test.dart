// Description: GrammarChecker rules (backlog item 11): lone i, a/an,
// repeated word, missing capital after a full stop; and what it must not flag.

import 'package:flutter/painting.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/utils/grammar_checker.dart';

List<GrammarIssue> _check(String s) => GrammarChecker.check(s);
List<String> _fixed(String s) => [for (final i in _check(s)) i.applyTo(s)];

void main() {
  group('lone i', () {
    test('flags i and its contractions, suggests I', () {
      final text = 'then i went home, and i\'m glad';
      final issues = _check(text);
      expect(issues.map((i) => i.ruleId), everyElement(GrammarRule.loneI));
      expect(issues.length, 2);
      expect(issues[0].range, const TextRange(start: 5, end: 6));
      expect(_fixed(text), ["then I went home, and i'm glad", "then i went home, and I'm glad"]);
    });

    test('does not flag i inside words, i.e., roman numerals, italics, parens', () {
      expect(_check('this is it, in time, i.e. nothing'), isEmpty);
      expect(_check('i. First item\nii. Second'), isEmpty);
      expect(_check('the letter *i* and (i) and \$i\$'), isEmpty);
    });

    test('a capital I is fine', () => expect(_check('I think so. I am.'), isEmpty));
  });

  group('a / an', () {
    test('a before a vowel sound becomes an', () {
      expect(_fixed('a apple and a orange'), ['an apple and a orange', 'a apple and an orange']);
      final i = _check('I ate a egg').single;
      expect(i.ruleId, GrammarRule.aAn);
      expect(i.range, const TextRange(start: 6, end: 7));
    });

    test('an before a consonant sound becomes a', () {
      expect(_fixed('an cat'), ['a cat']);
      expect(_fixed('We saw an dog.'), ['We saw a dog.']);
    });

    test('keeps the capital', () {
      expect(_fixed('A apple. An cat.'), ['An apple. An cat.', 'A apple. A cat.']);
    });

    test('exceptions: consonant sound after a vowel letter', () {
      for (final w in ['university', 'one-off', 'European', 'user', 'unit', 'useful', 'once', 'unicorn', 'eulogy', 'one']) {
        expect(_check('a $w'), isEmpty, reason: w);
      }
      expect(_check('an unusual thing, an urban area, an onerous task, an umbrella'), isEmpty);
    });

    test('exceptions: silent h', () {
      for (final w in ['hour', 'honest', 'honour', 'heir']) {
        expect(_check('an $w'), isEmpty, reason: w);
        expect(_fixed('a $w'), ['an $w'], reason: w);
      }
    });

    test('leaves acronyms, numbers, single letters, "an historic" alone', () {
      expect(_check('an FBI agent, a NASA probe, an 8, a 9, a x, an historic day'), isEmpty);
      expect(_check('Vitamin A is good. Plan A and B'), isEmpty);
    });

    test('flags across a marker but not across a line break', () {
      expect(_check('a **apple**').length, 1);
      expect(_check('a\napple'), isEmpty);
    });
  });

  group('repeated word', () {
    test('flags the second word; fix removes it with its space', () {
      const text = 'Over the the hill';
      final i = _check(text).single;
      expect(i.ruleId, GrammarRule.repeatedWord);
      expect(i.range, const TextRange(start: 9, end: 12));
      expect(i.applyTo(text), 'Over the hill');
    });

    test('case-insensitive, and not across lines or punctuation', () {
      expect(_fixed('The the end'), ['The end']);
      expect(_check('the\nthe'), isEmpty);
      expect(_check('the, the'), isEmpty);
      expect(_check('Dr. Dr.'), isEmpty);
      expect(_check('he had had enough, no no no'), isEmpty);
      expect(_check('year 2020 2020'), isEmpty);
    });
  });

  group('missing capital after a full stop', () {
    test('flags a lowercase start, fix capitalises it', () {
      const text = 'It rained. we left.';
      final i = _check(text).single;
      expect(i.ruleId, GrammarRule.capitalAfterStop);
      expect(i.range, const TextRange(start: 11, end: 12));
      expect(i.applyTo(text), 'It rained. We left.');
    });

    test('abbreviations and initials are not sentence ends', () {
      expect(_check('e.g. the cat, i.e. the dog, etc. and more'), isEmpty);
      expect(_check('Mr. smith and Mrs. jones and Dr. who'), isEmpty);
      expect(_check('J. k. rowling at 9 a.m. today'), isEmpty);
      expect(_check('the U.S. army'), isEmpty);
    });

    test('ellipsis, decimals, quotes after the stop are left alone', () {
      expect(_check('well... maybe'), isEmpty);
      expect(_check('it is 3.5 or so'), isEmpty);
      expect(_check('"Stop." she said'), isEmpty);
      expect(_check('Done. 3 things.'), isEmpty);
    });

    test('only lowercase letters after the stop', () => expect(_check('Yes. No. Maybe.'), isEmpty));
  });

  group('never flags markdown or code', () {
    test('inline code, fenced code, urls, markers', () {
      expect(_check('use `i = a apple. the the` here'), isEmpty);
      expect(_check('```\ni am a egg. the the\n```\n'), isEmpty);
      expect(_check('~~~\ni am\n~~~'), isEmpty);
      expect(_check('see https://example.com/a.b. and www.x.org. ok'), isEmpty);
      expect(_check('[home](http://a.com/i.the. and)'), isEmpty);
      expect(_check('1. first\n2. second\n- item\n- [ ] todo\n> quote\n# Title\n---\n'), isEmpty);
    });

    test('words around code still checked, and code breaks adjacency', () {
      expect(_check('the `x` the'), isEmpty);
      expect(_check('i `code` here').single.ruleId, GrammarRule.loneI);
    });

    test('an unclosed backtick is not code: later text is still checked', () {
      expect(_check('a stray ` tick. then more').single.ruleId, GrammarRule.capitalAfterStop);
    });
  });

  test('issues are sorted and non-overlapping', () {
    final issues = _check('it ended. i the the a apple');
    for (int k = 1; k < issues.length; k++) {
      expect(issues[k].range.start >= issues[k - 1].range.end, isTrue);
    }
  });

  test('empty and plain text', () {
    expect(_check(''), isEmpty);
    expect(_check('A perfectly fine sentence. And another one.'), isEmpty);
  });

  test('performance: 100k words checks quickly', () {
    final text = List.filled(20000, 'the quick brown fox jumps. Over a lazy dog.').join('\n');
    final sw = Stopwatch()..start();
    GrammarChecker.check(text);
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });
}
