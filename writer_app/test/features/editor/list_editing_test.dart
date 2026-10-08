// Description: Word-style lists (backlog items 2, 3, 8, 9, 10, 17): the Enter,
// Backspace and Undo rules for bullets, numbers and checklists, renumbering,
// nesting, the level-aware glyphs, and inline styles in heading/list lines.
// `|` marks the caret in the fixtures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/caret_formatting.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/list_editing.dart';
import 'package:pellucid/features/editor/list_marker.dart';
import 'package:pellucid/features/editor/marker_edit_rules.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/rich_clipboard.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

TextEditingValue v(String s) {
  final i = s.indexOf('|');
  return TextEditingValue(
    text: s.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: i),
  );
}

/// The value as `text` with `|` at the caret.
String show(TextEditingValue x) => x.text.replaceRange(x.selection.baseOffset, x.selection.baseOffset, '|');

/// Types [ins] at the caret of [from] through the editor's formatter.
TextEditingValue type(TextEditingValue from, String ins) {
  final s = from.selection;
  final text = from.text.replaceRange(s.start, s.end, ins);
  final next = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: s.start + ins.length));
  return applyMarkerEditRules(from, next);
}

TextEditingValue enter(String s) => type(v(s), '\n');

/// Backspace at the caret.
TextEditingValue backspace(String s) {
  final from = v(s);
  final p = from.selection.baseOffset;
  final next = TextEditingValue(
    text: from.text.replaceRange(p - 1, p, ''),
    selection: TextSelection.collapsed(offset: p - 1),
  );
  return applyMarkerEditRules(from, next);
}

void main() {
  setUp(() {
    listAutoContinueEnabled = true;
    lastAutoMarker = null;
  });

  group('bullets (item 2)', () {
    test('Enter at the end of a bullet continues the list', () {
      expect(show(enter('- one|')), '- one\n- |');
    });
    test('Enter in the middle splits the item', () {
      expect(show(enter('- one|two')), '- one\n- |two');
    });
    test('Enter on an empty bullet ends the list', () {
      expect(show(enter('- one\n- |')), '- one\n|');
    });
    test('Enter straight after the marker opens a line above (slice 4 rule kept)', () {
      expect(show(enter('- |one')), '\n- |one');
    });
    test('Enter on a non-list line is a plain line break', () {
      expect(show(enter('plain|')), 'plain\n|');
    });
    test('Backspace at the start removes the bullet, a second joins', () {
      expect(show(backspace('a\n- |b')), 'a\n|b');
      expect(show(backspace('a\n|b')), 'a|b');
    });
    test('Enter inside a bold run closes and reopens it after the marker', () {
      expect(show(enter('- **ab|cd**')), '- **ab**\n- **|cd**');
    });
    test('Enter at the end of a bold run leaves no empty markers', () {
      expect(show(enter('- **ab|**')), '- **ab**\n- |');
    });
    test('auto-continue switch off: Enter is a plain line break', () {
      listAutoContinueEnabled = false;
      expect(show(enter('- one|')), '- one\n|');
      // Ending an empty bullet by Enter is part of auto-continue too.
      expect(show(enter('- |')), '- \n|');
    });
    test('Undo straight after an automatic bullet removes just the bullet', () {
      final after = enter('- one|');
      final marker = lastAutoMarker!;
      expect(marker.applies(after), isTrue);
      expect(show(marker.undo()), '- one\n|');
    });
    test('the undo record is dropped by the next edit and by caret moves', () {
      final after = enter('- one|');
      final moved = after.copyWith(selection: const TextSelection.collapsed(offset: 0));
      expect(lastAutoMarker!.applies(moved), isFalse);
      type(after, 'x');
      expect(lastAutoMarker, isNull);
    });
  });

  group('nested items', () {
    test('Enter continues at the same level', () {
      expect(show(enter('- a\n    - b|')), '- a\n    - b\n    - |');
    });
    test('Enter on an empty nested item moves it out one level', () {
      expect(show(enter('- a\n    - |')), '- a\n- |');
    });
  });

  group('numbered lists (item 3)', () {
    test('Enter continues with the next number', () {
      expect(show(enter('1. a|')), '1. a\n2. |');
    });
    test('an item inserted in the middle renumbers the rest', () {
      expect(show(enter('1. a|\n2. b\n3. c')), '1. a\n2. |\n3. b\n4. c');
    });
    test('Enter on an empty numbered item ends the list', () {
      expect(show(enter('1. a\n2. |')), '1. a\n|');
    });
    test('removing an item (deleting its line) renumbers the rest', () {
      const from = TextEditingValue(text: '1. a\n2. b\n3. c\n4. d', selection: TextSelection(baseOffset: 5, extentOffset: 10));
      final next = TextEditingValue(text: '1. a\n3. c\n4. d', selection: const TextSelection.collapsed(offset: 5));
      expect(applyMarkerEditRules(from, next).text, '1. a\n2. c\n3. d');
    });
    test('Backspace at the start of an item takes its number off; the rest keep counting', () {
      expect(show(backspace('1. a\n2. |b\n3. c')), '1. a\n|b\n2. c');
    });
    test('digits growing from 9 to 10 are renumbered', () {
      final text = [for (int i = 1; i <= 9; i++) '$i. x'].join('\n');
      final r = enter('$text|');
      expect(r.text.split('\n').last, '10. ');
    });
    test('a list that starts at 3 keeps its start', () {
      expect(show(enter('3. a|\n4. b')), '3. a\n4. |\n5. b');
    });
    test('nested numbers count on their own', () {
      expect(enter('1. a\n    1. x|\n2. b').text, '1. a\n    1. x\n    2. \n2. b');
      expect(enter('1. a|\n    1. x\n2. b').text, '1. a\n2. \n    1. x\n3. b');
    });
    test('renumberLists touches only the list block around the edit', () {
      const text = '1. a\n1. b\n\n7. c\n7. d\n\nplain\n5. e\n5. f';
      // Block at the end only: the others keep their own numbers.
      final r = renumberLists(text, text.indexOf('5. e'), text.indexOf('5. e'));
      expect(r.text, '1. a\n1. b\n\n7. c\n7. d\n\nplain\n5. e\n6. f');
      expect(r.changes.length, 1);
    });
  });

  group('checklists (item 17)', () {
    test('Enter continues with an unticked box, even after a ticked one', () {
      expect(show(enter('- [x] done|')), '- [x] done\n- [ ] |');
    });
    test('Enter on an empty item ends the list; Backspace removes the box', () {
      expect(show(enter('- [ ] a\n- [ ] |')), '- [ ] a\n|');
      expect(show(backspace('- [ ] |a')), '|a');
    });
    test('toggleCheckbox flips the box and leaves the text alone', () {
      final on = toggleCheckbox(v('x\n- [ ] task|'), 2)!;
      expect(on.text, 'x\n- [x] task');
      expect(toggleCheckbox(on, 2)!.text, 'x\n- [ ] task');
      expect(toggleCheckbox(v('- plain'), 0), isNull);
    });
    test('checkboxLineAt: only the box (and the gap after it) counts', () {
      const t = 'a\n- [ ] task\n    - [x] sub';
      expect(checkboxLineAt(t, 2), 2); // before the box
      expect(checkboxLineAt(t, 3), 2); // between box and gap
      expect(checkboxLineAt(t, 4), isNull); // hidden filler / text
      expect(checkboxLineAt(t, 12), isNull);
      expect(checkboxLineAt(t, 0), isNull);
      final sub = t.indexOf('    - [x]');
      expect(checkboxLineAt(t, sub + 4), sub);
      expect(checkboxLineAt(t, sub + 2), isNull); // in the indent
    });
  });

  group('indent / unindent (item 8)', () {
    test('indent adds four spaces and nests under the item above', () {
      final r = indentLines(v('- a\n- b|'), outdent: false)!;
      expect(show(r), '- a\n    - b|');
    });
    test('cannot nest the first item, or deeper than one level below the one above', () {
      expect(indentLines(v('- a|'), outdent: false), isNull);
      expect(indentLines(v('- a\n    - b\n- c|'), outdent: false)!.text, '- a\n    - b\n    - c');
      expect(indentLines(v('- a\n    - b|'), outdent: false), isNull);
    });
    test('unindent removes one level; nothing at the margin', () {
      expect(show(indentLines(v('- a\n    - b|'), outdent: true)!), '- a\n- b|');
      expect(indentLines(v('- a|'), outdent: true), isNull);
      expect(indentLines(v('plain|'), outdent: true), isNull);
      // Plain paragraphs take a paragraph indent now (slice 5b): see paragraph_indent_test.dart.
      expect(show(indentLines(v('plain|'), outdent: false)!), '\u2003plain|');
    });
    test('a tab indent unindents too', () {
      expect(indentLines(v('- a\n\t- b|'), outdent: true)!.text, '- a\n- b');
    });
    test('indenting a numbered item restarts a nested list at 1 and closes up the rest', () {
      final r = indentLines(v('1. a\n2. b\n3. c|\n4. d'), outdent: false)!;
      expect(r.text, '1. a\n2. b\n    1. c\n3. d');
    });
    test('indenting under an existing nested list continues it', () {
      final r = indentLines(v('1. a\n    1. x\n    2. y\n2. b|'), outdent: false)!;
      expect(r.text, '1. a\n    1. x\n    2. y\n    3. b');
    });
    test('unindenting a numbered item joins the list above', () {
      final r = indentLines(v('1. a\n2. b\n    1. c|\n    2. d'), outdent: true)!;
      expect(r.text, '1. a\n2. b\n3. c\n    1. d');
    });
    test('a selection over several lines moves every list line in it', () {
      const sel = TextSelection(baseOffset: 4, extentOffset: 10);
      final r = indentLines(const TextEditingValue(text: '- a\n- b\n- c\n- d', selection: sel), outdent: false)!;
      expect(r.text, '- a\n    - b\n    - c\n- d');
      expect(r.selection.start, 8);
    });
    test('selectionTouchesList', () {
      expect(selectionTouchesList('plain\n- a', const TextSelection.collapsed(offset: 2)), isFalse);
      expect(selectionTouchesList('plain\n- a', const TextSelection.collapsed(offset: 8)), isTrue);
      expect(selectionTouchesList('plain\n- a', const TextSelection(baseOffset: 0, extentOffset: 8)), isTrue);
    });
  });

  group('line style toggles (items 2, 3, 17)', () {
    MarkdownEditingController c(String s) {
      final x = v(s);
      return MarkdownEditingController(text: x.text, theme: WriterTheme.presets[0])..selection = x.selection;
    }

    test('numbered and checklist toggle on, off, and replace each other', () {
      final a = c('item|')..toggleFormat('1. ');
      expect(a.text, '1. item');
      a.toggleFormat('1. ');
      expect(a.text, 'item');
      a.toggleFormat('- [ ] ');
      expect(a.text, '- [ ] item');
      a.toggleFormat('- ');
      expect(a.text, '- item');
      a.toggleFormat('1. ');
      expect(a.text, '1. item');
    });
    test('a new numbered line counts on from the list above', () {
      final a = c('1. a\n2. b\nc|')..toggleFormat('1. ');
      expect(a.text, '1. a\n2. b\n3. c');
    });
    test('taking a number off the middle item closes the gap', () {
      final a = c('1. a\n2. b|\n3. c')..toggleFormat('1. ');
      expect(a.text, '1. a\nb\n2. c');
    });
    test('Body strips any list marker and indent', () {
      final a = c('    - [x] done|')..toggleFormat('body');
      expect(a.text, 'done');
    });
    test('indent / outdent through toggleFormat', () {
      final a = c('- a\n- b|')..toggleFormat('indent');
      expect(a.text, '- a\n    - b');
      a.toggleFormat('outdent');
      expect(a.text, '- a\n- b');
    });
    test('formattingAt reports the list kind', () {
      expect(formattingAt('- a', const TextSelection.collapsed(offset: 3)).list, ListStyle.bullet);
      expect(formattingAt('    7. a', const TextSelection.collapsed(offset: 8)).list, ListStyle.numbered);
      expect(formattingAt('- [x] a', const TextSelection.collapsed(offset: 7)).list, ListStyle.checklist);
      expect(formattingAt('- [x] a', const TextSelection.collapsed(offset: 7)).block, BlockStyle.body);
    });
  });

  group('level-aware glyphs (items 9, 10)', () {
    ListGlyph g(String line) => listGlyph(parseListMarker(line)!);

    test('bullets go • ◦ ▪ by level and round again', () {
      expect(g('- a').shown, '• ');
      expect(g('    - a').shown, '◦ ');
      expect(g('        - a').shown, '▪ ');
      expect(g('            - a').shown, '• ');
      expect(g('  - a').shown, '◦ '); // a two-space indent from another editor nests too
    });
    test('numbers go 1. a. i. by level', () {
      expect(g('3. a').shown, '3. ');
      expect(g('    3. a').shown, 'c. ');
      expect(g('        3. a').shown, 'iii. ');
      expect(g('        3. a').absorbed, 2);
      expect(g('            3. a').shown, '3. ');
    });
    test('a label too long for its room falls back to the stored number', () {
      expect(g('        38. a').shown, '38. ');
      expect(g('  3. a').shown, 'c. ');
    });
    test('the drawn marker is exactly as long as the stored one', () {
      for (final line in ['- a', '    - a', '1. a', '    10. a', '        4. a', '        8. a', '- [ ] a', '  - [x] a', '\t\t12. a']) {
        final m = parseListMarker(line)!;
        final x = listGlyph(m);
        expect(m.indent.length - x.absorbed + x.shown.length + x.pad, m.length, reason: line);
      }
    });
    test('the stored Markdown is untouched by drawing', () {
      final c = MarkdownEditingController(text: '- a\n    - b\n        1. c', theme: WriterTheme.presets[0]);
      expect(c.text, '- a\n    - b\n        1. c');
    });
  });

  group('inline styles in heading and list lines (owner request)', () {
    testWidgets('bold and italic render, and their stars are hidden', (tester) async {
      final c = MarkdownEditingController(
          text: '# T **b**\n- a *i*\n1. x **y**\n- [ ] z ~~s~~\n> q **w**', theme: WriterTheme.presets[0]);
      late TextSpan root;
      await tester.pumpWidget(Builder(builder: (context) {
        root = c.buildTextSpan(context: context, style: const TextStyle(), withComposing: false);
        return const SizedBox();
      }));
      final leaves = <TextSpan>[];
      void walk(InlineSpan s) {
        if (s is! TextSpan) return;
        if (s.text != null) leaves.add(s);
        s.children?.forEach(walk);
      }

      walk(root);
      bool has(String text, bool Function(TextStyle) test) =>
          leaves.any((s) => s.text == text && s.style != null && test(s.style!));
      expect(has('b', (st) => st.fontWeight == FontWeight.bold && st.fontSize == 32), isTrue);
      expect(has('i', (st) => st.fontStyle == FontStyle.italic), isTrue);
      expect(has('y', (st) => st.fontWeight == FontWeight.bold), isTrue);
      expect(has('s', (st) => st.decoration == TextDecoration.lineThrough), isTrue);
      // The stars are there, but invisible.
      expect(has('**', (st) => st.color == Colors.transparent), isTrue);
      expect(root.toPlainText(), contains('**'));
    });

    test('caret rules still apply: markers are hidden on heading and list lines', () {
      const t = '# T **b** x';
      final line = scanLineAt(t, 0);
      expect(line.runs.map((r) => r.tag), ['**']);
      expect(visibleText(t), 'T b x');
      // Backspace at the start of the heading still removes the heading first.
      expect(show(backspace('# |T **b**')), '|T **b**');
      // Deleting the last letter of the bold run in a bullet removes the markers.
      expect(show(backspace('- a **b|** c')), '- a | c');
    });
  });

  group('copy out of the editor', () {
    const t = '- a\n1. b **c**\n2. d\n- [ ] e\n- [x] f';
    test('plain text shows the markers a reader sees', () {
      expect(plainTextFor(t, 0, t.length), '• a\n1. b c\n2. d\n☐ e\n☑ f');
    });
    test('HTML uses ul and ol', () {
      final h = htmlFor(t, 0, t.length);
      expect(h, contains('<ul><li>a</li></ul><ol><li>b <strong>c</strong></li>'));
      expect(h, contains('<li>d</li></ol><ul><li>'));
    });
  });
}
