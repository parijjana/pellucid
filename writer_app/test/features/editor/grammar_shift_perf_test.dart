// Description: Per-keystroke grammar-hint shifting must not rescan the whole
// document once per hint, and must give the same ranges as the old per-hint code.

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
    final sw = Stopwatch()..start();
    final oldSw = Stopwatch();
    var cur = text;
    for (var k = 0; k < keystrokes; k++) {
      final next = cur.replaceRange(mid, mid, 'x');
      final expected = (oldSw..start(), _oldShift(c.grammarIssues, cur, next), oldSw..stop()).$2;
      sw.start();
      c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: mid + 1));
      sw.stop();
      expect([for (final i in c.grammarIssues) (i.range, i.fixRange, i.replacement, i.ruleId)],
          [for (final i in expected) (i.range, i.fixRange, i.replacement, i.ruleId)]);
      cur = next;
    }
    final newMs = sw.elapsedMicroseconds / 1000 / keystrokes;
    final oldMs = oldSw.elapsedMicroseconds / 1000 / keystrokes;
    // ignore: avoid_print
    print('grammar shift per keystroke: old ${oldMs.toStringAsFixed(2)} ms, new ${newMs.toStringAsFixed(2)} ms');
    expect(newMs, lessThan(100)); // generous: holds under machine load
  });
}
