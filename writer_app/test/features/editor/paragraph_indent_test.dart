// Description: Paragraph indent (slice 5b, backlog item 8). Indent / Unindent on
// ordinary paragraphs store one U+2003 EM SPACE per level (max 4) at the start
// of the line: other Markdown apps show an indent and no code block. The editor
// hides the run like a marker, indents the line by one list level per em space,
// rests the caret after the run, and Backspace / Enter treat it as indent.
// `|` marks the caret in the fixtures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/list_editing.dart';
import 'package:pellucid/features/editor/marker_edit_rules.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pellucid/features/editor/services/export_markdown.dart';
import 'package:pellucid/features/editor/services/export_pdf_lists.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

const String em = ' ';

TextEditingValue v(String s) {
  final i = s.indexOf('|');
  return TextEditingValue(text: s.replaceFirst('|', ''), selection: TextSelection.collapsed(offset: i));
}

String show(TextEditingValue x) => x.text.replaceRange(x.selection.baseOffset, x.selection.baseOffset, '|');

TextEditingValue type(TextEditingValue from, String ins) {
  final s = from.selection;
  final text = from.text.replaceRange(s.start, s.end, ins);
  return applyMarkerEditRules(from, TextEditingValue(text: text, selection: TextSelection.collapsed(offset: s.start + ins.length)));
}

TextEditingValue backspace(String s) {
  final from = v(s);
  final p = from.selection.baseOffset;
  return applyMarkerEditRules(
      from, TextEditingValue(text: from.text.replaceRange(p - 1, p, ''), selection: TextSelection.collapsed(offset: p - 1)));
}

void main() {
  group('storage', () {
    test('the Dart markdown parser does not make a code block of em spaces', () {
      for (final lvl in [1, 2, 3, 4]) {
        final html = md.markdownToHtml('${em * lvl}Indented paragraph');
        expect(html, isNot(contains('<pre>')), reason: 'level $lvl');
        expect(html, isNot(contains('<code>')), reason: 'level $lvl');
        expect(html, startsWith('<p>'));
        expect(html, contains('Indented paragraph'));
      }
      // The spaces version, for contrast: this is why em spaces are used.
      expect(md.markdownToHtml('    Indented'), contains('<pre>'));
    });

    test('the export HTML turns the run into a class and never prints it', () {
      final html = markdownToExportHtml('${em * 2}First line\n${em * 2}soft break\n\nPlain\n\n```\n${em}code\n```\n');
      expect(html, contains('<p class="in2">First line\nsoft break</p>'));
      expect(html, contains('<p>Plain</p>'));
      expect(html, contains('${em}code')); // code is verbatim
      expect(html.replaceAll('${em}code', ''), isNot(contains(em)));
    });
  });

  test('PDF pads an indented paragraph by one list level (18 pt) per em space', () async {
    final widgets = await markdownToPdfWidgets('${em * 2}Indented\n\nPlain');
    final pads = widgets.whereType<pw.Padding>().toList();
    expect(pads, hasLength(1));
    expect((pads.single.padding as pw.EdgeInsets).left, 36);
  });

  group('indent / unindent', () {
    TextEditingValue? indent(String s, {bool out = false}) => indentLines(v(s), outdent: out);

    test('adds one em space per level at the line start, caret moves with the text', () {
      expect(show(indent('Hel|lo')!), '${em}Hel|lo');
      expect(show(indent('${em}Hel|lo')!), '${em * 2}Hel|lo');
    });

    test('stops at four levels', () {
      expect(indent('${em * 4}Hello'), isNull);
    });

    test('unindent removes one level and does nothing at the margin', () {
      expect(show(indent('${em * 2}Hel|lo', out: true)!), '${em}Hel|lo');
      expect(indent('Hello', out: true), isNull);
    });

    test('a multi-line selection indents each paragraph; blanks, headings, quotes and code are skipped', () {
      final text = 'one\n\n# Head\n> quote\n```\ncode\n```\ntwo';
      final r = indentLines(
          TextEditingValue(text: text, selection: TextSelection(baseOffset: 0, extentOffset: text.length)),
          outdent: false)!;
      expect(r.text, '${em}one\n\n# Head\n> quote\n```\ncode\n```\n${em}two');
    });

    test('list items and paragraphs are handled together', () {
      final text = '- a\n- b\nplain';
      final r = indentLines(
          TextEditingValue(text: text, selection: TextSelection(baseOffset: 0, extentOffset: text.length)),
          outdent: false)!;
      expect(r.text, '- a\n    - b\n${em}plain');
    });

    test('a list line still indents as a list', () {
      expect(show(indent('- a\n- b|')!), '- a\n    - b|');
    });
  });

  group('editing', () {
    test('Backspace at the start of an indented paragraph removes one level', () {
      expect(show(backspace('$em$em|Hello')), '$em|Hello');
      expect(show(backspace('$em|Hello')), '|Hello');
    });

    test('Backspace elsewhere on the line deletes a letter', () {
      expect(show(backspace('${em}He|llo')), '${em}H|llo');
    });

    test('Enter carries the indent to the new line', () {
      expect(show(type(v('$em$em' 'Hello|'), '\n')), '$em${em}Hello\n$em$em|');
      expect(show(type(v('${em}He|llo'), '\n')), '${em}He\n$em|llo');
    });

    test('Enter on an empty indented line takes a level off, no new line', () {
      expect(show(type(v('$em$em|'), '\n')), '$em|');
    });

    test('Enter on an unindented paragraph is untouched', () {
      expect(show(type(v('Hello|'), '\n')), 'Hello\n|');
    });

    test('the new indented line is one Undo step (marker undo)', () {
      type(v('${em}Hello|'), '\n');
      expect(lastAutoMarker, isNotNull);
    });
  });

  group('hidden marker and caret rules', () {
    test('the run is a hidden prefix; the caret rests after it', () {
      const t = '$em${em}Hello';
      final line = scanLineAt(t, 0);
      expect(line.isParagraphIndent, isTrue);
      expect(line.hidden.single, const TextRange(start: 0, end: 2));
      for (final o in [0, 1, 2]) {
        expect(canonicalOffset(t, o), 2, reason: 'offset $o');
      }
      expect(stepLeft(t, 3), isNot(1));
      expect(stepRight(t, 0), 3);
    });

    test('visibleText keeps the indent as space', () {
      expect(visibleText('$em**b** x'), '${em}b x');
    });
  });

  group('rendering', () {
    final theme = WriterTheme.presets[0];

    testWidgets('em spaces are a transparent span in the stored length, one list level wide each', (tester) async {
      final c = MarkdownEditingController(text: '${em * 2}Hello\n    - item', theme: theme);
      late TextSpan root;
      await tester.pumpWidget(Builder(builder: (context) {
        root = c.buildTextSpan(context: context, style: const TextStyle(fontFamily: 'Georgia'), withComposing: false);
        return const SizedBox();
      }));
      expect(root.toPlainText().length, c.text.length);
      final first = root.children!.first as TextSpan;
      expect(first.text, em * 2);
      expect(first.style!.color, Colors.transparent);

      // Sized so one em space is about one list level (four spaces at 18 px).
      expect(first.style!.fontSize, inInclusiveRange(8.0, 24.0));
    });
  });
}
