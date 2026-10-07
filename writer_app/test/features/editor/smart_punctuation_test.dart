// Description: Smart punctuation (backlog item 27): quotes, em dash, ellipsis,
// code exclusions, and single-step undo of just the conversion.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/core/platform_context.dart';
import 'package:pellucid/features/editor/utils/smart_punctuation.dart';
import 'package:pellucid/features/editor/widgets/smart_punctuation_scope.dart';

/// Types [input] one character at a time through a fresh formatter.
String _type(String input, {String start = '', SmartPunctuationFormatter? formatter}) {
  final f = formatter ?? SmartPunctuationFormatter();
  var v = TextEditingValue(text: start, selection: TextSelection.collapsed(offset: start.length));
  for (final ch in input.split('')) {
    final next = TextEditingValue(
      text: v.text.replaceRange(v.selection.start, v.selection.end, ch),
      selection: TextSelection.collapsed(offset: v.selection.start + 1),
    );
    v = f.formatEditUpdate(v, next);
  }
  return v.text;
}

void main() {
  group('quotes', () {
    test('double quotes open and close by context', () {
      expect(_type('"Hello," she said.'), '“Hello,” she said.');
      expect(_type('He said "hi" to me'), 'He said “hi” to me');
      expect(_type('("x")'), '(“x”)');
      expect(_type('a\n"b"'), 'a\n“b”');
      expect(_type('—"Go!"'), '—“Go!”');
    });

    test('single quotes: apostrophes close, openers open', () {
      expect(_type("don't"), 'don’t');
      expect(_type("it's Tom's"), 'it’s Tom’s');
      expect(_type("'quoted'"), '‘quoted’');
      expect(_type('"He said \'no\'"'), '“He said ‘no’”');
      expect(_type("the 1990's"), 'the 1990’s');
      expect(_type("dogs' bowls"), 'dogs’ bowls');
    });

    test('closing quote after punctuation', () {
      expect(_type('"Wait."'), '“Wait.”');
      expect(_type('"Wait!"'), '“Wait!”');
      expect(_type('"Wait…"'), '“Wait…”');
    });
  });

  group('dash and ellipsis', () {
    test('-- becomes an em dash', () {
      expect(_type('wait--what'), 'wait—what');
      expect(_type('a -- b'), 'a — b');
    });

    test('a single hyphen, and --- rules, tables, comments are left alone', () {
      expect(_type('well-known'), 'well-known');
      expect(_type('---'), '---');
      expect(_type('a\n---'), 'a\n---');
      expect(_type('|---|'), '|---|');
      expect(_type('<!--'), '<!--');
    });

    test('... becomes an ellipsis', () {
      expect(_type('wait...'), 'wait…');
      expect(_type('and so...on'), 'and so…on');
    });

    test('two dots and a fourth dot stay', () {
      expect(_type('end..'), 'end..');
      expect(_type('end....'), 'end….');
    });
  });

  group('never inside code', () {
    test('inline code', () {
      expect(_type('`say "hi" -- it\'s...`'), '`say "hi" -- it\'s...`');
      expect(_type('`a" b`" c"'), '`a" b`” c”');
    });

    test('unclosed inline code (still typing it)', () {
      expect(_type('`it\'s'), '`it\'s');
    });

    test('fenced code block', () {
      expect(_type('x', start: '```\nsay "hi" -- ok...\n'), '```\nsay "hi" -- ok...\nx');
      expect(_type('"q"', start: '```\ncode\n```\n'), '```\ncode\n```\n“q”');
      expect(_type('"', start: '```\ncode\n'), '```\ncode\n"');
    });
  });

  group('only genuine single keystrokes', () {
    test('paste, multi-char and replace-all edits are untouched', () {
      final f = SmartPunctuationFormatter();
      final pasted = f.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '"a" -- b...', selection: TextSelection.collapsed(offset: 11)),
      );
      expect(pasted.text, '"a" -- b...');
    });

    test('typing a quote over a selection', () {
      final f = SmartPunctuationFormatter();
      final out = f.formatEditUpdate(
        const TextEditingValue(text: 'say hi', selection: TextSelection(baseOffset: 4, extentOffset: 6)),
        const TextEditingValue(text: 'say "', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(out.text, 'say “');
    });

    test('switched off', () {
      expect(_type('"hi" -- ok...', formatter: SmartPunctuationFormatter(enabled: false)), '"hi" -- ok...');
    });

    test('selection range stays collapsed after the converted text', () {
      final f = SmartPunctuationFormatter();
      var v = const TextEditingValue(text: 'a-', selection: TextSelection.collapsed(offset: 2));
      v = f.formatEditUpdate(
        v,
        const TextEditingValue(text: 'a--', selection: TextSelection.collapsed(offset: 3)),
      );
      expect(v.text, 'a—');
      expect(v.selection, const TextSelection.collapsed(offset: 2));
    });
  });

  group('undo of the last conversion', () {
    test('undoLast restores the keystroke as typed, once', () {
      final f = SmartPunctuationFormatter();
      var v = const TextEditingValue(text: 'a-', selection: TextSelection.collapsed(offset: 2));
      v = f.formatEditUpdate(
        v,
        const TextEditingValue(text: 'a--', selection: TextSelection.collapsed(offset: 3)),
      );
      expect(f.canUndo(v), isTrue);
      final back = f.undoLast(v)!;
      expect(back.text, 'a--');
      expect(back.selection, const TextSelection.collapsed(offset: 3));
      expect(f.undoLast(v), isNull);
    });

    test('no undo once the writer typed on or moved the caret', () {
      final f = SmartPunctuationFormatter();
      final v = f.formatEditUpdate(
        const TextEditingValue(text: 'x', selection: TextSelection.collapsed(offset: 1)),
        const TextEditingValue(text: 'x"', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(v.text, 'x”');
      expect(f.canUndo(v.copyWith(selection: const TextSelection.collapsed(offset: 0))), isFalse);
      final next = f.formatEditUpdate(
        v,
        const TextEditingValue(text: 'x”y', selection: TextSelection.collapsed(offset: 3)),
      );
      expect(f.canUndo(next), isFalse);
      expect(f.lastConversion, isNull);
    });
  });

  group('widget: one Undo key press takes back only the conversion', () {
    Future<(TextEditingController, List<String>)> pump(WidgetTester tester, {bool enabled = true}) async {
      final controller = TextEditingController();
      final saved = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SmartPunctuationScope(
            enabled: enabled,
            controller: controller,
            onChanged: saved.add,
            builder: (context, formatters) => TextField(
              controller: controller,
              inputFormatters: formatters,
              autofocus: true,
              maxLines: null,
            ),
          ),
        ),
      ));
      await tester.pump();
      return (controller, saved);
    }

    Future<void> undoKey(WidgetTester tester) async {
      final modifier = usesCommandModifier ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    testWidgets('typing converts, Undo restores the dashes, text and autosave agree', (tester) async {
      final (controller, saved) = await pump(tester);
      await tester.enterText(find.byType(TextField), 'wait-');
      await tester.enterText(find.byType(TextField), 'wait--');
      expect(controller.text, 'wait—');
      await undoKey(tester);
      expect(controller.text, 'wait--');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      expect(saved.last, 'wait--');
    });

    testWidgets('quote: Undo leaves the straight quote', (tester) async {
      final (controller, _) = await pump(tester);
      await tester.enterText(find.byType(TextField), '"');
      expect(controller.text, '“');
      await undoKey(tester);
      expect(controller.text, '"');
    });

    testWidgets('disabled: nothing converts', (tester) async {
      final (controller, _) = await pump(tester, enabled: false);
      await tester.enterText(find.byType(TextField), 'a--');
      expect(controller.text, 'a--');
    });
  });
}
