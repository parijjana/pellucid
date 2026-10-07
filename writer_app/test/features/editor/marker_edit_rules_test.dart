// Description: Editing with hidden markers (backlog item 24): each keyboard
// edit is rewritten so markdown markers stay balanced and never show raw.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/marker_edit_rules.dart';

TextEditingValue _v(String text, int base, [int? extent]) =>
    TextEditingValue(text: text, selection: TextSelection(baseOffset: base, extentOffset: extent ?? base));

/// What EditableText proposes for each key, before the rules run.
TextEditingValue backspace(String t, int p) =>
    applyMarkerEditRules(_v(t, p), _v(t.substring(0, p - 1) + t.substring(p), p - 1));
TextEditingValue forwardDelete(String t, int p) =>
    applyMarkerEditRules(_v(t, p), _v(t.substring(0, p) + t.substring(p + 1), p));
TextEditingValue type(String t, int s, String ins, [int? e]) {
  final end = e ?? s;
  return applyMarkerEditRules(_v(t, s, end), _v(t.replaceRange(s, end, ins), s + ins.length));
}

void expectValue(TextEditingValue v, String text, int caret) {
  expect(v.text, text);
  expect(v.selection, TextSelection.collapsed(offset: caret));
}

void main() {
  group('Backspace at the start of a block line removes the style first', () {
    test('heading becomes body, then a second Backspace joins lines', () {
      //                       0123 4567
      final once = backspace('ab\n# Head', 5);
      expectValue(once, 'ab\nHead', 3);
      expectValue(backspace(once.text, 3), 'abHead', 2);
    });
    test('bullet and subheading prefixes too', () {
      expectValue(backspace('- item', 2), 'item', 0);
      expectValue(backspace('### Sub', 4), 'Sub', 0);
    });
    test('Backspace inside heading text is ordinary', () {
      expectValue(backspace('# Head', 4), '# Had', 3);
    });
  });

  group('Backspace/Delete never eat a hidden marker', () {
    test('forward delete before a run deletes its first letter', () {
      //                           0123456789
      expectValue(forwardDelete('a**bold** z', 1), 'a**old** z', 1);
    });
    test('backspace from just after a closing marker deletes the last letter', () {
      expectValue(backspace('a**bold** z', 9), 'a**bol** z', 6);
    });
    test('forward delete at the end of a run deletes the next visible char', () {
      expectValue(forwardDelete('**ab** z', 4), '**ab**z', 4);
    });
    test('forward delete joining a heading line drops its prefix', () {
      expectValue(forwardDelete('ab\n# Head', 2), 'abHead', 2);
    });
  });

  group('deleting the last character of a run removes its markers', () {
    test('bold', () => expectValue(backspace('a**b** c', 4), 'a c', 1));
    test('underline', () => expectValue(backspace('a<u>b</u>', 5), 'a', 1));
    test('bold-italic', () => expectValue(backspace('***x***', 4), '', 0));
    test('nested runs empty out together', () => expectValue(backspace('**<u>x</u>**', 6), '', 0));
  });

  group('selection deletes across a run boundary leave balanced markers', () {
    //          0123456789
    const t = 'ab**cd**ef';
    test('selection starts outside, ends inside', () {
      // "b**c" selected.
      expectValue(type(t, 1, '', 5), 'a**d**ef', 1);
    });
    test('selection starts inside, ends outside', () {
      // "d**e" selected.
      expectValue(type(t, 5, '', 9), 'ab**c**f', 5);
    });
    test('selection covering a whole run removes it', () {
      expectValue(type(t, 1, '', 9), 'af', 1);
    });
    test('selection ending inside an opening marker', () {
      // "b*" selected (ends between the two stars).
      expectValue(type(t, 1, '', 3), 'a**cd**ef', 1);
    });
    test('selection starting inside a closing marker', () {
      // "*e" selected (starts between the two closing stars).
      expectValue(type(t, 7, '', 9), 'ab**cd**f', 6);
    });
    test('selection that empties a run drops its markers', () {
      expectValue(type(t, 1, '', 7), 'aef', 1);
    });
    test('typed replacement takes the style of the first selected letter', () {
      expectValue(type(t, 4, 'X', 9), 'ab**X**f', 5);
      expectValue(type(t, 1, 'X', 5), 'aX**d**ef', 2);
    });
    test('a selection across lines into a heading joins it as body text', () {
      expectValue(type('ab\n# Head', 1, '', 6), 'aead', 1);
    });
  });

  group('line breaks', () {
    test('Enter inside a run closes and reopens it', () {
      expectValue(type('**abcd**', 4, '\n'), '**ab**\n**cd**', 7);
    });
    test('Enter at the end of a run leaves no empty run behind', () {
      expectValue(type('**ab** z', 4, '\n'), '**ab**\n z', 7);
    });
    test('Enter right after a heading prefix opens a line above', () {
      expectValue(type('# Head', 2, '\n'), '\n# Head', 3);
    });
    test('Enter on an empty heading line is ordinary', () {
      expectValue(type('# ', 2, '\n'), '# \n', 3);
    });
  });

  test('typing at a caret is untouched', () {
    expectValue(type('**ab** z', 4, 'x'), '**abx** z', 5);
    expectValue(type('**ab** z', 0, 'x'), 'x**ab** z', 1);
  });

  test('IME composition is left alone', () {
    const old = TextEditingValue(text: 'a**b**', selection: TextSelection.collapsed(offset: 1));
    const composing = TextEditingValue(
      text: 'a´**b**',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 1, end: 2),
    );
    expect(applyMarkerEditRules(old, composing), composing);
  });

  group('toggling a style with no selection', () {
    test('at the end of a run ends it there', () {
      final t = toggleInlineAtCaret('**ab** z', 4, '**')!;
      expect(t.text, '**ab** z');
      expect(t.caret, 6);
      expect(t.pendingEmptyRun, isNull);
    });
    test('in the middle of a run splits it', () {
      final t = toggleInlineAtCaret('**abcd**', 4, '**')!;
      expect(t.text, '**ab****cd**');
      expect(t.caret, 6);
    });
    test('outside any run opens an empty run for the next keystroke', () {
      final t = toggleInlineAtCaret('ab cd', 2, '<u>')!;
      expect(t.text, 'ab<u></u> cd');
      expect(t.caret, 5);
      expect(t.pendingEmptyRun, const TextRange(start: 2, end: 9));
    });
    test('ending bold at the end of bold-italic keeps italic', () {
      final t = toggleInlineAtCaret('***ab***', 5, '**')!;
      expect(t.text, '***ab*****');
      expect(t.caret, 9);
      final typed = type(t.text, t.caret, 'x');
      expect(typed.text, '***ab****x*');
    });
    test('refused on heading lines and where stars would re-pair', () {
      expect(toggleInlineAtCaret('# Head', 4, '**'), isNull);
      expect(toggleInlineAtCaret('*abcd*', 3, '**'), isNull);
    });
  });

  group('MarkerCaret', () {
    test('a collapsed caret inside markers is moved to its resting place', () {
      final caret = MarkerCaret();
      final v = caret.adjust(_v('a**bold**', 0), _v('a**bold**', 2));
      expect(v.selection.baseOffset, 1);
    });
    test('selections are not moved', () {
      final caret = MarkerCaret();
      final v = caret.adjust(_v('a**bold**', 0), _v('a**bold**', 2, 5));
      expect(v.selection, const TextSelection(baseOffset: 2, extentOffset: 5));
    });
    test('the toggle spot is kept until the caret moves; an untouched empty run is removed', () {
      final caret = MarkerCaret();
      final t = toggleInlineAtCaret('ab cd', 2, '**')!;
      caret.setToggle(t);
      caret.adjust(_v('ab cd', 2), _v(t.text, t.caret));
      final kept = caret.adjust(_v(t.text, t.caret), _v(t.text, t.caret));
      expect(kept.selection.baseOffset, t.caret);
      final moved = caret.adjust(_v(t.text, t.caret), _v(t.text, 8));
      expect(moved.text, 'ab cd');
      expect(moved.selection.baseOffset, 4);
    });
    test('typing into the empty run keeps it', () {
      final caret = MarkerCaret();
      final t = toggleInlineAtCaret('ab cd', 2, '**')!;
      caret.setToggle(t);
      caret.adjust(_v('ab cd', 2), _v(t.text, t.caret));
      final typed = caret.adjust(_v(t.text, t.caret), _v('ab**x** cd', 5));
      expect(typed.text, 'ab**x** cd');
      expect(caret.sticky, isNull);
    });
  });
}
