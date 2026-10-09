// Description: Per-keystroke grammar-hint shifting must not rescan the whole
// document once per hint, and must give the same ranges as the old per-hint code.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/utils/grammar_checker.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

/// The pre-fix behaviour: one full prefix/suffix scan per hint.
List<GrammarIssue> _oldShift(List<GrammarIssue> issues, String oldText, String newText) => [
      for (final i in issues)
        if (MarkdownEditingController.shiftRangesForEdit([i.range, i.fixRange], oldText, newText)
            case [final r, final f])
          GrammarIssue(range: r, fixRange: f, replacement: i.replacement, ruleId: i.ruleId, message: i.message),
    ];

String _doc() {
  final b = StringBuffer();
  for (var w = 0; w < 100000; w += 200) {
    b.write('Some plain words go here and then the the cat sat. ');
    for (var k = 0; k < 190; k++) {
      b.write('word${k % 7} ');
    }
    b.write('\n');
  }
  return b.toString();
}

void main() {
  test('keystroke shift: same ranges as before, and fast with 500 hints in 100k words', () {
    final text = _doc();
    final issues = GrammarChecker.check(text);
    expect(issues.length, greaterThan(400));

    final c = MarkdownEditingController(text: text, theme: WriterTheme.presets[0]);
    c.setGrammarIssues(issues);

    final mid = text.length ~/ 2;
    const keystrokes = 20;
    // Time only the controller edit; the old per-hint code runs afterwards so
    // its garbage cannot land inside the timed region.
    final sw = Stopwatch();
    final steps = <(List<GrammarIssue> before, String oldText, String newText, List<GrammarIssue> after)>[];
    var cur = text;
    for (var k = 0; k < keystrokes; k++) {
      final next = cur.replaceRange(mid, mid, 'x');
      final before = c.grammarIssues;
      sw.start();
      c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: mid + 1));
      sw.stop();
      steps.add((before, cur, next, c.grammarIssues));
      cur = next;
    }
    final oldSw = Stopwatch();
    for (final s in steps) {
      oldSw.start();
      final expected = _oldShift(s.$1, s.$2, s.$3);
      oldSw.stop();
      expect([for (final i in s.$4) (i.range, i.fixRange, i.replacement, i.ruleId)],
          [for (final i in expected) (i.range, i.fixRange, i.replacement, i.ruleId)]);
    }
    final newMs = sw.elapsedMicroseconds / 1000 / keystrokes;
    final oldMs = oldSw.elapsedMicroseconds / 1000 / keystrokes;
    // ignore: avoid_print
    print('grammar shift per keystroke: old ${oldMs.toStringAsFixed(2)} ms, new ${newMs.toStringAsFixed(2)} ms');
    // Goal is < 5 ms; 25 ms leaves room for machine load (it takes ~1 ms idle).
    expect(newMs, lessThan(25));
  });

  test('selection-based edit span: kept ranges still cover the same text after random edits', () {
    final rnd = Random(7);
    for (var round = 0; round < 300; round++) {
      final old = String.fromCharCodes([for (var k = 0; k < 200; k++) 97 + rnd.nextInt(3)]);
      final ranges = <TextRange>[];
      for (var p = 0; p < old.length - 4;) {
        p += rnd.nextInt(8);
        final len = 1 + rnd.nextInt(4);
        if (p + len > old.length) break;
        ranges.add(TextRange(start: p, end: p + len));
        p += len;
      }
      final a = rnd.nextInt(old.length);
      final b = a + rnd.nextInt(min(6, old.length - a));
      final ins = String.fromCharCodes([for (var k = rnd.nextInt(5); k > 0; k--) 97 + rnd.nextInt(3)]);
      final next = old.replaceRange(a, b, ins);
      if (next == old) continue;
      final c = MarkdownEditingController(text: old, theme: WriterTheme.presets[0]);
      c.setMisspellings(ranges);
      // Caret placements: after the edit (typing/backspace), or somewhere odd.
      final caret = rnd.nextBool() ? a + ins.length : rnd.nextInt(next.length + 1);
      c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: caret));
      // Repeated characters make the edit position ambiguous (any valid
      // explanation of the same text is fine), so check what matters: every
      // kept range still covers the same text, and they stay sorted.
      final kept = c.misspellings;
      for (var k = 0; k < kept.length; k++) {
        expect(kept[k].end, lessThanOrEqualTo(next.length));
        if (k > 0) expect(kept[k].start, greaterThanOrEqualTo(kept[k - 1].end));
      }
      final oldTexts = [for (final r in ranges) (r.start, old.substring(r.start, r.end))];
      var oi = 0;
      for (final r in kept) {
        final t = next.substring(r.start, r.end);
        while (oi < oldTexts.length && oldTexts[oi].$2 != t) {
          oi++;
        }
        expect(oi < oldTexts.length, isTrue, reason: 'kept range text must exist in the old ranges, in order');
        oi++;
      }
    }
  });
}
