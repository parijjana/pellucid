// Description: The incremental grammar re-check must equal a full check
// exactly, for any sequence of edits.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/utils/grammar_checker.dart';

const _bits = [
  'i ', 'I ', 'a apple ', 'an cat ', 'the the ', 'dog ', 'cat. ', 'cat. then ', 'Mr. smith ', 'i.e. x ',
  'hour ', 'a university ', '\n', '\n\n', '\n', '  ', '\t', '- ', '1. ', '# ', '> ', '`code the the` ',
  'http://x.y/a the the ', '[link](http://a.b) ', '**bold** ', '_it_ ', "i'm ", 'x. y. ', '...', '(i) ',
  '\n\n\n', '\r\n', 'ii. ', 'A ', 'AN ', 'word ', 'words ', 'a ', 'an ', 'the ', '.', ' ',
];
const _fence = ['```\n', '~~~\n'];

String _randText(Random r, int n, {bool fences = false}) {
  final b = StringBuffer();
  for (var k = 0; k < n; k++) {
    b.write(fences && r.nextInt(40) == 0 ? _fence[r.nextInt(2)] : _bits[r.nextInt(_bits.length)]);
  }
  return b.toString();
}

String _edit(Random r, String t, {bool fences = false}) {
  final a = t.isEmpty ? 0 : r.nextInt(t.length + 1);
  final len = r.nextInt(4) == 0 ? r.nextInt(30) : r.nextInt(3);
  final b = (a + len).clamp(0, t.length);
  final ins = r.nextInt(3) == 0 ? '' : _randText(r, 1 + r.nextInt(3), fences: fences);
  return t.replaceRange(a, b, ins);
}

List<Object> _key(List<GrammarIssue> l) => [for (final i in l) '${i.range}${i.fixRange}${i.replacement}${i.ruleId}${i.message}'];

void main() {
  test('incremental == full over random edits (with and without fences)', () {
    final r = Random(42);
    for (final fences in [false, true]) {
      for (var round = 0; round < 150; round++) {
        var text = _randText(r, 5 + r.nextInt(80), fences: fences);
        var issues = GrammarChecker.check(text);
        for (var step = 0; step < 12; step++) {
          var next = _edit(r, text, fences: fences);
          if (r.nextInt(4) == 0) next = _edit(r, next, fences: fences); // several edits between checks
          final inc = GrammarChecker.checkIncremental(text, issues, next);
          final full = GrammarChecker.check(next);
          expect(_key(inc), _key(full), reason: 'fences=$fences round=$round step=$step\nold: ${text.codeUnits}\nnew: ${next.codeUnits}');
          text = next;
          issues = inc;
        }
      }
    }
  });

  test('incremental handles empty, identical and whole-document changes', () {
    for (final (a, b) in [('', 'i am'), ('i am', ''), ('i am', 'i am'), ('the the', 'a apple\n\nthe the'), ('x', 'i went. then')]) {
      expect(_key(GrammarChecker.checkIncremental(a, GrammarChecker.check(a), b)), _key(GrammarChecker.check(b)));
    }
  });

  test('incremental re-check is much cheaper than a full one on a long document', () {
    final b = StringBuffer();
    for (var k = 0; k < 2000; k++) {
      b.write('Some plain words go here and then the the cat sat. i went to a apple tree today.\n\n');
    }
    final old = b.toString();
    final issues = GrammarChecker.check(old);
    final mid = old.length ~/ 2;
    final next = old.replaceRange(mid, mid, 'the the ');
    final fullSw = Stopwatch()..start();
    final full = GrammarChecker.check(next);
    fullSw.stop();
    final incSw = Stopwatch()..start();
    final inc = GrammarChecker.checkIncremental(old, issues, next);
    incSw.stop();
    expect(_key(inc), _key(full));
    // ignore: avoid_print
    print('grammar recheck: full ${fullSw.elapsedMilliseconds} ms, incremental ${incSw.elapsedMilliseconds} ms');
    expect(incSw.elapsedMilliseconds * 3, lessThan(fullSw.elapsedMilliseconds + 1));
  });
}
