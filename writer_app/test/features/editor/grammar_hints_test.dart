// Description: Grammar-hint underline in MarkdownEditingController (dotted,
// theme-aware, distinct from the wavy spell-check one) and the lookup/fix API
// the right-click menu will call.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/utils/grammar_checker.dart';
import 'package:pellucid/features/editor/utils/grammar_hint_style.dart';
import 'package:pellucid/features/editor/widgets/grammar_hints.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

List<TextSpan> _flatten(InlineSpan root) {
  final out = <TextSpan>[];
  void collect(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null && span.text!.isNotEmpty) out.add(span);
      span.children?.forEach(collect);
    }
  }
  collect(root);
  return out;
}

void main() {
  final theme = WriterTheme.presets[0];

  Future<List<TextSpan>> spansFor(WidgetTester tester, MarkdownEditingController c) async {
    late List<TextSpan> spans;
    await tester.pumpWidget(Builder(builder: (context) {
      spans = _flatten(c.buildTextSpan(context: context, style: const TextStyle(), withComposing: false));
      return const SizedBox();
    }));
    return spans;
  }

  test('contrast: every theme preset gets a hint colour at 3:1 or better, not red', () {
    for (final t in WriterTheme.presets) {
      final c = grammarHintColor(t);
      expect(contrastRatio(c, t.backgroundColor), greaterThanOrEqualTo(3.0), reason: t.name);
      // Never the spell-check reds.
      expect(c, isNot(const Color(0xFFD32F2F)), reason: t.name);
      expect(c, isNot(const Color(0xFFFF5370)), reason: t.name);
    }
  });

  testWidgets('hint is a dotted underline in the hint colour, markdown styling kept', (tester) async {
    final c = MarkdownEditingController(text: '# the the Title', theme: theme);
    c.setGrammarIssues(GrammarChecker.check(c.text));
    expect(c.grammarIssues.length, 1);
    final spans = await spansFor(tester, c);

    final hint = spans.firstWhere((s) => s.style?.decorationStyle == TextDecorationStyle.dotted);
    expect(hint.text, 'the');
    expect(hint.style!.decoration, TextDecoration.underline);
    expect(hint.style!.decorationColor, grammarHintColor(theme));
    expect(hint.style!.fontSize, 32.0);
    expect(spans.where((s) => s.style?.decorationStyle == TextDecorationStyle.wavy), isEmpty);
    expect(spans.firstWhere((s) => s.text == '# ').style!.color, Colors.transparent);
  });

  testWidgets('spelling and grammar underlines coexist', (tester) async {
    final c = MarkdownEditingController(text: 'i wrod here', theme: theme);
    c.setGrammarIssues(GrammarChecker.check(c.text));
    c.setMisspellings([const TextRange(start: 2, end: 6)]);
    final spans = await spansFor(tester, c);
    expect(spans.firstWhere((s) => s.text == 'i').style!.decorationStyle, TextDecorationStyle.dotted);
    expect(spans.firstWhere((s) => s.text == 'wrod').style!.decorationStyle, TextDecorationStyle.wavy);
  });

  test('grammarIssueAt finds the hint under an offset', () {
    final c = MarkdownEditingController(text: 'then i went', theme: theme);
    c.setGrammarIssues(GrammarChecker.check(c.text));
    expect(c.grammarIssueAt(5)?.ruleId, GrammarRule.loneI);
    expect(c.grammarIssueAt(6)?.ruleId, GrammarRule.loneI); // caret just after
    expect(c.grammarIssueAt(0), isNull);
    expect(c.grammarIssueAt(9), isNull);
  });

  test('applyGrammarFix edits the text and moves the caret after the change', () {
    final c = MarkdownEditingController(text: 'Over the the hill', theme: theme);
    c.setGrammarIssues(GrammarChecker.check(c.text));
    final issue = c.grammarIssueAt(10)!;
    expect(c.applyGrammarFix(issue), isTrue);
    expect(c.text, 'Over the hill');
    expect(c.selection, const TextSelection.collapsed(offset: 8));
    // The hint went with the edit; the stale one cannot be applied twice.
    expect(c.grammarIssues, isEmpty);
    expect(c.applyGrammarFix(issue), isFalse);
  });

  test('hints before an edit stay, hints after it move, hints touched by it go', () {
    final c = MarkdownEditingController(text: 'i went. a apple. the the end', theme: theme);
    c.setGrammarIssues(GrammarChecker.check(c.text));
    final before = c.grammarIssues.map((i) => i.ruleId).toList();
    expect(before.length, greaterThanOrEqualTo(3));
    c.value = TextEditingValue(
      text: 'i went. XX a apple. the the end',
      selection: const TextSelection.collapsed(offset: 11),
    );
    expect(c.grammarIssues.first.range, const TextRange(start: 0, end: 1));
    final apple = c.grammarIssues.firstWhere((i) => i.ruleId == GrammarRule.aAn);
    expect(c.text.substring(apple.range.start, apple.range.end), 'a');
    expect(apple.range.start, 11);
  });
}
