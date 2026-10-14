// Applying bold/italic/underline/strikethrough to a selection must always
// leave balanced markers: the 1.1.0 owner report showed raw `~~...*` and
// `~~*word` after formatting a selection that touched an existing run.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/caret_formatting.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

void main() {
  final theme = WriterTheme.presets.first;

  MarkdownEditingController make(String text, int a, int b) =>
      MarkdownEditingController(text: text, theme: theme)..selection = TextSelection(baseOffset: a, extentOffset: b);

  bool on(String text, TextSelection s, String tag) {
    final f = formattingAt(text, s);
    return switch (tag) { '**' => f.bold, '*' => f.italic, '<u>' => f.underline, _ => f.strikethrough };
  }

  group('selection toggles that used to leave raw markers', () {
    test('strike over a selection that contains a struck run (was ~~~~a ...~~ x~~)', () {
      final c = make('does ~~this feel~~ any', 0, 22)..toggleFormat('~~');
      expect(c.text, '~~does this feel any~~');
    });

    test('italic over text that starts inside a struck run does not cross it', () {
      final c = make('~~one two~~ three', 6, 17)..toggleFormat('*');
      expect(visibleText(c.text), 'one two three');
      expect(c.text, '~~one ~~*~~two~~ three*');
    });

    test('whitespace at the edges stays outside the markers', () {
      final c = make('say  hello  now', 3, 12)..toggleFormat('*');
      expect(c.text, 'say  *hello*  now');
    });

    test('a selection over a line break is wrapped line by line', () {
      final c = make('one two\nthree four', 4, 13)..toggleFormat('~~');
      expect(c.text, 'one ~~two~~\n~~three~~ four');
      c.toggleFormat('~~');
      expect(c.text, 'one two\nthree four');
    });

    test('strike then italic then both off, undone in order', () {
      final c = make('production', 0, 10);
      c.toggleFormat('~~');
      expect(c.text, '~~production~~');
      c.toggleFormat('*');
      expect(c.text, '~~*production*~~');
      c.toggleFormat('~~');
      expect(c.text, '*production*');
      c.toggleFormat('*');
      expect(c.text, 'production');
    });

    test('turning a style off in the middle of a run splits it', () {
      final c = make('*abc def ghi*', 5, 8)..toggleFormat('*');
      expect(visibleText(c.text), 'abc def ghi');
      expect(on(c.text, TextSelection(baseOffset: c.selection.start, extentOffset: c.selection.end), '*'), isFalse);
    });
  });

  test('every selection x two toggles over runs of every style stays balanced and flips the style', () {
    const tags = ['<u>', '*', '~~', '**'];
    const bases = [
      'does ~~this feel~~ any',
      'does *this feel* any',
      'does <u>this</u> *feel* any',
      'a ***b*** c',
      'x ~~*y*~~ z',
      'one\n~~two~~ three  ',
    ];
    final problems = <String>[];
    for (final src in bases) {
      final plain = visibleText(src);
      for (int a = 0; a < src.length; a++) {
        for (int b = a + 1; b <= src.length; b++) {
          for (final t in tags) {
            for (final t2 in tags) {
              final c = make(src, a, b);
              final before = on(src, c.selection, t);
              final hasVisible = RegExp(r'\S').hasMatch(visibleText(src.substring(a, b)));
              c.toggleFormat(t);
              if (hasVisible && c.text != src && visibleText(c.text) == plain) {
                if (on(c.text, c.selection, t) == before) problems.add('flip [$t] [$a,$b] "$src" -> "${c.text}"');
              }
              c.toggleFormat(t2);
              if (visibleText(c.text) != plain) problems.add('text [$t,$t2] [$a,$b] "$src" -> "${c.text}"');
            }
          }
        }
      }
    }
    expect(problems.take(10).toList(), isEmpty, reason: '${problems.length} problems');
  });

  group('selection that includes a heading line (E2E-8a)', () {
    const text = 'first body\n## A heading\nsecond body';

    test('bold applies to the body lines and skips the heading', () {
      final c = make(text, 0, text.length)..toggleFormat('**');
      expect(c.text, '**first body**\n## A heading\n**second body**');
    });

    test('bold again on the same selection removes it from the body lines', () {
      final c = make(text, 0, text.length)..toggleFormat('**');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleFormat('**');
      expect(c.text, text);
    });

    test('italic skips the heading too', () {
      final c = make(text, 0, text.length)..toggleFormat('*');
      expect(c.text, '*first body*\n## A heading\n*second body*');
    });

    test('a selection of only a heading still does nothing', () {
      final c = make(text, 11, 22)..toggleFormat('**');
      expect(c.text, text);
    });
  });
}
