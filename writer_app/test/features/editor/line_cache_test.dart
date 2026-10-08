// Description: The per-line span cache in MarkdownEditingController must never
// change what is drawn. A cached controller and an uncached one are driven
// through the same random edits and state changes; their spans must be equal
// after every step.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/utils/grammar_checker.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import 'large_document_fixture.dart';

void main() {
  testWidgets('cached spans equal uncached spans through random edits', (tester) async {
    final rnd = Random(23);
    final themes = WriterTheme.presets;
    final cached = MarkdownEditingController(text: generateManuscript(3000), theme: themes[0]);
    final plain = MarkdownEditingController(text: cached.text, theme: themes[0])..lineCacheEnabled = false;
    const titles = [CodexTitle(id: 'n1', title: 'Mira'), CodexTitle(id: 'n2', title: 'Ostrava')];
    cached.codexTitles = titles;
    plain.codexTitles = titles;
    const snippets = [
      'a', ' ', '\n', '**', '*', '# ', '- ', 'Mira ', 'Teh', '<u>x</u>', '\n\n', '😀',
      // Slice 6 formats and slice 8 grammar triggers.
      '~~', '~~gone~~', '\n> ', '> ', '\n### ', '### ', ' i ', ' the the ', '. lower', ' a apple',
      // Slice 5: lists, checklists, nesting, and inline styles on block lines.
      '\n- ', '\n1. ', '\n12. ', '\n- [ ] ', '\n- [x] ', '- [ ] ', '1. ', '    ', '\n    - ', '\n        3. ',
      '\n    - [x] ', '\n  2. ', '[x]', '# **b**', '- *i* ',
    ];
    const styles = [
      TextStyle(fontSize: 16, fontFamily: 'Georgia'),
      TextStyle(fontSize: 16, fontFamily: 'Helvetica Neue'),
      TextStyle(fontSize: 20, fontFamily: 'Menlo'),
    ];
    var style = styles[0];

    List<TextRange> misspellingsOf(String text) =>
        [for (final m in RegExp(r'\b(Teh|recieved)\b').allMatches(text)) TextRange(start: m.start, end: m.end)];

    late BuildContext ctx;
    await tester.pumpWidget(Builder(builder: (context) {
      ctx = context;
      return const SizedBox();
    }));

    for (int step = 0; step < 400; step++) {
      final text = cached.text;
      final roll = rnd.nextInt(12);
      if (roll < 5) {
        // Type or delete somewhere, like a keystroke.
        final at = rnd.nextInt(text.length + 1);
        final String next = rnd.nextBool() || at == 0
            ? text.replaceRange(at, at, snippets[rnd.nextInt(snippets.length)])
            : text.replaceRange(at - 1, at, '');
        final value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: at.clamp(0, next.length)));
        cached.value = value;
        plain.value = value;
      } else if (roll == 5) {
        final ranges = misspellingsOf(text);
        cached.setMisspellings(ranges);
        plain.setMisspellings(ranges);
      } else if (roll == 6) {
        final q = ['', 'tide', 'Mira', '*', 'a'][rnd.nextInt(5)];
        cached.searchQuery = q;
        plain.searchQuery = q;
        final hits = q.isEmpty ? <Match>[] : RegExp(RegExp.escape(q), caseSensitive: false).allMatches(text).toList();
        final active = hits.isEmpty ? -1 : hits[rnd.nextInt(hits.length)].start;
        cached.activeMatchOffset = active;
        plain.activeMatchOffset = active;
      } else if (roll == 7) {
        final on = rnd.nextBool();
        cached.paragraphFocusEnabled = on;
        plain.paragraphFocusEnabled = on;
        final sel = TextSelection.collapsed(offset: rnd.nextInt(text.length + 1));
        cached.selection = sel;
        plain.selection = sel;
      } else if (roll == 8) {
        final on = rnd.nextBool();
        cached.codexLinkingEnabled = on;
        plain.codexLinkingEnabled = on;
      } else if (roll == 9) {
        final t = themes[rnd.nextInt(themes.length)];
        cached.theme = t;
        plain.theme = t;
      } else if (roll == 10) {
        // Grammar hints (slice 8) are drawn per line, so they key the cache.
        final issues = GrammarChecker.check(text);
        cached.setGrammarIssues(issues);
        plain.setGrammarIssues(issues);
      } else {
        // Document font (slice 6) reaches buildTextSpan as the base style.
        style = styles[rnd.nextInt(styles.length)];
      }
      final a = cached.buildTextSpan(context: ctx, style: style, withComposing: false);
      final b = plain.buildTextSpan(context: ctx, style: style, withComposing: false);
      expect(a, b, reason: 'step $step (roll $roll)');
    }
  });
}
