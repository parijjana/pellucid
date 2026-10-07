// Description: Backlog item 30: large manuscripts must keep their formatted
// view. MarkdownEditingController has no size limit; these tests pin that
// down and check the invariant EditableText relies on: the span tree's plain
// text equals the controller text character for character, so caret,
// selection and hit-testing offsets line up at any size.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import 'large_document_fixture.dart';

List<TextSpan> _flatten(InlineSpan root) {
  final List<TextSpan> out = [];
  void collect(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null && span.text!.isNotEmpty) out.add(span);
      span.children?.forEach(collect);
    }
  }
  collect(root);
  return out;
}

/// What the editor should draw: the document text with each bullet's "- "
/// shown as "• ". Same length, so every offset lines up.
String _drawn(String text) => text.replaceAllMapped(RegExp(r'^- ', multiLine: true), (_) => '• ');

void main() {
  final theme = WriterTheme.presets[0];

  Future<TextSpan> build(WidgetTester tester, MarkdownEditingController c) async {
    late TextSpan span;
    await tester.pumpWidget(Builder(builder: (context) {
      span = c.buildTextSpan(context: context, style: const TextStyle(), withComposing: false);
      return const SizedBox();
    }));
    return span;
  }

  /// Turns on every styling layer the controller has.
  void allLayersOn(MarkdownEditingController c) {
    final text = c.text;
    c.codexTitles = const [CodexTitle(id: 'n1', title: 'Mira'), CodexTitle(id: 'n2', title: 'Ostrava')];
    c.codexLinkingEnabled = true;
    c.searchQuery = 'tide';
    c.paragraphFocusEnabled = true;
    c.selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final List<TextRange> miss = [];
    for (final m in RegExp(r'\b(Teh|recieved)\b').allMatches(text)) {
      miss.add(TextRange(start: m.start, end: m.end));
    }
    c.setMisspellings(miss);
  }

  testWidgets('a bullet line keeps span text aligned with the document text', (tester) async {
    final c = MarkdownEditingController(text: '- one\n- two\nafter', theme: theme);
    final span = await build(tester, c);
    expect(span.toPlainText(), _drawn(c.text));
    // The bullet still shows as a dot, not a dash.
    expect(_flatten(span).any((s) => s.text!.contains('•')), isTrue);
  });

  testWidgets('"***a**" keeps its own characters: closing marker is "**"', (tester) async {
    final c = MarkdownEditingController(text: 'x ***a** y', theme: theme);
    final span = await build(tester, c);
    expect(span.toPlainText(), c.text);
  });

  for (final words in [1000, 20000, 100000, 500000]) {
    testWidgets('$words-word manuscript keeps its formatted view', (tester) async {
      final text = generateManuscript(words);
      final c = MarkdownEditingController(text: text, theme: theme);
      allLayersOn(c);
      final span = await build(tester, c);
      final spans = _flatten(span);

      expect(span.toPlainText(), _drawn(text), reason: 'span text must match the document');
      // Heading markers hidden, headings and bold actually styled.
      expect(spans.any((s) => s.text == '# ' && s.style?.color == Colors.transparent), isTrue);
      expect(spans.any((s) => s.style?.fontSize == 32.0), isTrue);
      expect(spans.any((s) => s.style?.fontWeight == FontWeight.bold && s.style?.fontSize == null), isTrue);
      expect(spans.any((s) => s.style?.decorationStyle == TextDecorationStyle.wavy), isTrue);
      expect(spans.any((s) => s.style?.backgroundColor != null), isTrue);
    });
  }

  testWidgets('fuzz: random markdown-ish text never throws or drifts', (tester) async {
    final rnd = Random(30);
    const alphabet = ['*', '**', '<u>', '</u>', '# ', '## ', '### ', '- ', '\n', ' ', 'a', 'é', '😀', 'Mira'];
    for (int i = 0; i < 400; i++) {
      final b = StringBuffer();
      final n = rnd.nextInt(60);
      for (int j = 0; j < n; j++) {
        b.write(alphabet[rnd.nextInt(alphabet.length)]);
      }
      final text = b.toString();
      final c = MarkdownEditingController(text: text, theme: theme);
      allLayersOn(c);
      c.searchQuery = '*';
      final span = await build(tester, c);
      expect(span.toPlainText(), _drawn(text), reason: 'input: ${text.replaceAll('\n', r'\n')}');
    }
  });
}
