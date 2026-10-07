// Item 16: Subheading (H3, `### `) in the controller, the table of contents
// and the toolbar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/utils/toc_parser.dart';
import 'package:pellucid/features/editor/widgets/formatting_toolbar.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

void main() {
  final theme = WriterTheme.presets.first;

  MarkdownEditingController make(String text, int caret) =>
      MarkdownEditingController(text: text, theme: theme)
        ..selection = TextSelection.collapsed(offset: caret);

  group('toggleFormat("### ")', () {
    test('turns a body line into a subheading', () {
      final c = make('Hello', 2)..toggleFormat('### ');
      expect(c.text, '### Hello');
    });

    test('switches Heading to Subheading and back to Body', () {
      final c = make('## Hello', 3)..toggleFormat('### ');
      expect(c.text, '### Hello');
      c.toggleFormat('### ');
      expect(c.text, 'Hello');
    });

    test('Body strips the three hashes', () {
      final c = make('### Hello', 4)..toggleFormat('body');
      expect(c.text, 'Hello');
    });
  });

  testWidgets('H3 span: marker transparent, content 18pt bold', (tester) async {
    final c = make('### Sub', 0);
    late TextSpan span;
    await tester.pumpWidget(Builder(builder: (ctx) {
      span = c.buildTextSpan(context: ctx, withComposing: false);
      return const SizedBox();
    }));
    final leaves = <TextSpan>[];
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null) leaves.add(s);
      return true;
    });
    expect(leaves.first.text, '### ');
    expect(leaves.first.style!.color, Colors.transparent);
    expect(leaves[1].text, 'Sub');
    expect(leaves[1].style!.fontSize, 18.0);
    expect(leaves[1].style!.fontWeight, FontWeight.bold);
  });

  test('table of contents lists level-3 headers under their chapter', () {
    final h = parseTocHeaders('# Book\n## Part\n### Sub\nthree words here\n');
    expect(h.map((e) => e.level), [1, 2, 3]);
    expect(h[2].title, 'Sub');
    expect(h[2].wordCount, 3);
    expect(h[0].wordCount, 3);
  });

  testWidgets('toolbar has a SUBHEAD button that applies "### "', (tester) async {
    String? applied;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FormattingToolbar(theme: theme, onApplyFormat: (f) => applied = f),
      ),
    ));
    await tester.tap(find.text('SUBHEAD'));
    expect(applied, '### ');
  });
}
