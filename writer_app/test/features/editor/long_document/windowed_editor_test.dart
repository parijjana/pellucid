import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/long_document/document_buffer.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import '../large_document_fixture.dart';

const _style = TextStyle(fontSize: 16, height: 1.8, color: Colors.black);

Future<WindowedEditorState> _pump(WidgetTester tester, MarkdownEditingController doc,
    {ValueChanged<String>? onChanged}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<WindowedEditorState>();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WindowedEditor(
        key: key,
        controller: doc,
        focusNode: FocusNode(),
        theme: doc.theme,
        style: _style,
        pageWidth: 800,
        horizontalPosition: 0.5,
        cursorColor: Colors.black,
        onChanged: onChanged ?? (_) {},
      ),
    ),
  ));
  await tester.pump();
  return key.currentState!;
}

/// The window is exactly lines [first, last) of the buffer, and the document
/// controller, the buffer and the window all agree.
void _expectCoherent(WindowedEditorState s, MarkdownEditingController doc, String reference) {
  expect(doc.text, reference);
  expect(s.buffer.text, reference);
  expect(s.window.windowStart, s.buffer.lineStart(s.span.first));
  expect(s.window.text, s.buffer.textOfLines(s.span.first, s.span.last));
  final ws = s.window.windowStart, we = ws + s.window.text.length;
  final wide = doc.selection.isValid && (doc.selection.start < ws || doc.selection.end > we);
  if (s.window.selection.isValid && doc.selection.isValid && !wide) {
    expect(doc.selection.baseOffset, s.window.selection.baseOffset + s.window.windowStart);
    expect(doc.selection.extentOffset, s.window.selection.extentOffset + s.window.windowStart);
  }
}

/// Never between the two halves of a surrogate pair (real input never is).
int _snap(String t, int o) => o > 0 && o < t.length && (t.codeUnitAt(o) & 0xFC00) == 0xDC00 ? o + 1 : o;

/// Types like the platform does: a new value on the field's controller.
void _typeInWindow(WindowedEditorState s, int at, int removeLen, String inserted) {
  final w = s.window;
  final int end = _snap(w.text, min(w.text.length, at + removeLen));
  w.value = TextEditingValue(
    text: w.text.replaceRange(at, end, inserted),
    selection: TextSelection.collapsed(offset: at + inserted.length),
  );
}

void main() {
  test('planWindow keeps whole lines around the selection within the budget', () {
    final b = DocumentBuffer(List.generate(1000, (i) => 'line $i with some words').join('\n'));
    final caret = b.lineStart(500) + 3;
    final w = debugPlanWindow(b, caret, caret);
    expect(w.first <= 500 && 500 < w.last, isTrue);
    final size = b.lineEnd(w.last - 1) - b.lineStart(w.first);
    expect(size, greaterThanOrEqualTo(kWindowBudgetChars));
    expect(size, lessThan(kWindowBudgetChars + 60));
    final top = debugPlanWindow(b, 0, 0);
    expect(top.first, 0);
    final all = debugPlanWindow(DocumentBuffer('short\ndoc'), 2, 2);
    expect((all.first, all.last), (0, 2));
  });

  testWidgets('a long document shows a live window, not the whole text', (tester) async {
    final text = generateManuscript(20000, seed: 5, markupEvery: 200);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    expect(s.window.text.length, lessThan(text.length ~/ 10));
    expect(s.span.first, greaterThan(0));
    expect(s.span.last, lessThan(s.buffer.lineCount));
    _expectCoherent(s, doc, text);
  });

  testWidgets('random typing, deleting and caret jumps keep the document byte-identical', (tester) async {
    final rnd = Random(9);
    String reference = generateManuscript(15000, seed: 2, markupEvery: 80);
    final doc = MarkdownEditingController(text: reference, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: reference.length ~/ 3);
    String? lastChanged;
    final s = await _pump(tester, doc, onChanged: (t) => lastChanged = t);
    const pieces = ['x', 'y', ' ', '\n', 'word', '**b** ', '\n\n', 'é', '😀'];
    for (int step = 0; step < 250; step++) {
      final int roll = rnd.nextInt(10);
      if (roll < 6) {
        // Type or replace inside the window, near the caret.
        final w = s.window;
        final int caret = w.selection.isValid ? w.selection.extentOffset : 0;
        final int at = _snap(w.text, (caret + rnd.nextInt(41) - 20).clamp(0, w.text.length));
        final int remove = rnd.nextInt(4) == 0 ? rnd.nextInt(6) : 0;
        final String ins = pieces[rnd.nextInt(pieces.length)];
        final int docAt = w.windowStart + at;
        final int docEnd = w.windowStart + _snap(w.text, min(w.text.length, at + remove));
        reference = reference.replaceRange(docAt, docEnd, ins);
        _typeInWindow(s, at, remove, ins);
      } else if (roll < 8) {
        // Caret walks to the window edge (arrow keys / typing past it).
        final w = s.window;
        final int to = rnd.nextBool() ? 0 : w.text.length;
        w.selection = TextSelection.collapsed(offset: to);
      } else {
        // A jump from outside (Find, TOC): set the document selection.
        doc.selection = TextSelection.collapsed(offset: _snap(reference, rnd.nextInt(reference.length + 1)));
      }
      await tester.pump();
      await tester.pump();
      _expectCoherent(s, doc, reference);
    }
    expect(s.windowMoves, greaterThan(10), reason: 'the window moved across the document');
    expect(lastChanged, reference);
  });

  testWidgets('an edit made outside the window (formatting, Replace) reaches the window', (tester) async {
    String reference = generateManuscript(8000, seed: 4);
    final doc = MarkdownEditingController(text: reference, theme: WriterTheme.presets[0])
      ..selection = const TextSelection.collapsed(offset: 10);
    final s = await _pump(tester, doc);
    final int far = reference.length - 50;
    reference = reference.replaceRange(far, far + 4, 'EDIT');
    doc.value = TextEditingValue(text: reference, selection: TextSelection.collapsed(offset: far + 4));
    await tester.pump();
    await tester.pump();
    _expectCoherent(s, doc, reference);
    expect(s.window.text, contains('EDIT'));
  });

  testWidgets('undo and redo work on the document across window moves', (tester) async {
    final original = generateManuscript(12000, seed: 8);
    final doc = MarkdownEditingController(text: original, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: original.length ~/ 2);
    final s = await _pump(tester, doc);
    final int at = s.window.selection.extentOffset;
    for (final ch in 'abc'.split('')) {
      _typeInWindow(s, s.window.selection.extentOffset, 0, ch);
      await tester.pump();
    }
    final typed = doc.text;
    expect(typed, original.replaceRange(s.window.windowStart + at, s.window.windowStart + at, 'abc'));
    // Move far away, then undo: the typing run comes out in one step.
    doc.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    await tester.pump();
    s.undo();
    await tester.pump();
    await tester.pump();
    expect(doc.text, original);
    s.redo();
    await tester.pump();
    await tester.pump();
    expect(doc.text, typed);
    _expectCoherent(s, doc, typed);
  });

  testWidgets('composing text holds the window still until it is committed', (tester) async {
    final text = generateManuscript(12000, seed: 6);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    final moves = s.windowMoves;
    final w = s.window;
    final int end = w.text.length;
    final int docEnd = w.windowStart + end;
    // An accent being composed at the window's last character.
    w.value = TextEditingValue(
      text: '${w.text}´',
      selection: TextSelection.collapsed(offset: end + 1),
      composing: TextRange(start: end, end: end + 1),
    );
    await tester.pump();
    await tester.pump();
    expect(s.windowMoves, moves, reason: 'no move while composing');
    // Commit: é replaces the composing accent.
    w.value = TextEditingValue(text: '${w.text.substring(0, end)}é', selection: TextSelection.collapsed(offset: end + 1));
    await tester.pump();
    await tester.pump();
    expect(s.windowMoves, greaterThan(moves));
    expect(doc.text, text.replaceRange(docEnd, docEnd, 'é'));
  });

  testWidgets('a click on a static line moves the window there', (tester) async {
    final text = generateManuscript(12000, seed: 7);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    final int before = s.span.first;
    // Scroll up into the static lines above the window (the window starts at 0).
    s.scroll.jumpTo(-600);
    await tester.pump();
    final finder = find.byType(RichText).first;
    await tester.tapAt(tester.getTopLeft(finder) + const Offset(2, 2));
    await tester.pump();
    await tester.pump();
    expect(s.span.first, isNot(before));
    expect(doc.selection.isCollapsed, isTrue, reason: '${doc.selection}');
    final line = s.buffer.lineOfOffset(doc.selection.baseOffset);
    expect(line >= s.span.first && line < s.span.last, isTrue, reason: 'line $line, window ${s.span}');
    expect(line, lessThan(before), reason: 'the tapped line is above the old window');
  });

  test('static line spans keep the line length (hit-testing needs same-length text)', () {
    final doc = MarkdownEditingController(text: '', theme: WriterTheme.presets[0]);
    final text = generateManuscript(3000, seed: 12, markupEvery: 20);
    for (final line in text.split('\n')) {
      final scratch = MarkdownEditingController(text: line, theme: doc.theme);
      final spans = scratch.buildLineSpans(dim: false, style: _style);
      expect(TextSpan(children: spans).toPlainText().length, line.length, reason: line);
    }
  });

  testWidgets('Select All then typing replaces the whole document; undo brings it back', (tester) async {
    final text = generateManuscript(20000, seed: 13);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    final first = s.span.first;
    s.selectAll();
    await tester.pump();
    expect(doc.selection, TextSelection(baseOffset: 0, extentOffset: text.length));
    expect(s.span.first, first, reason: 'Select All does not move the window');
    expect(s.window.selection, TextSelection(baseOffset: 0, extentOffset: s.window.text.length));
    // The field replaces what it sees; the document replaces everything.
    _typeInWindow(s, 0, s.window.text.length, 'x');
    await tester.pump();
    await tester.pump();
    expect(doc.text, 'x');
    _expectCoherent(s, doc, 'x');
    s.undo();
    await tester.pump();
    await tester.pump();
    expect(doc.text, text);
    _expectCoherent(s, doc, text);
  });

  testWidgets('a backspace over a selection reaching past the window deletes all of it', (tester) async {
    final text = generateManuscript(40000, seed: 14);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    final int a = s.window.windowStart + 10;
    final int b = text.length - 100; // far below the window, > the cap
    expect(b - a, greaterThan(kWindowSelectionCapChars));
    doc.selection = TextSelection(baseOffset: a, extentOffset: b);
    await tester.pump();
    await tester.pump();
    final clamped = s.window.selection;
    expect(clamped.isCollapsed, isFalse);
    _typeInWindow(s, clamped.start, clamped.end - clamped.start, '');
    await tester.pump();
    await tester.pump();
    final expected = text.replaceRange(a, b, '');
    _expectCoherent(s, doc, expected);
    expect(doc.selection, TextSelection.collapsed(offset: a));
  });

  testWidgets('mouse drag across static lines selects them, then the window takes the selection', (tester) async {
    final text = generateManuscript(12000, seed: 15);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    final before = s.span.first;
    s.scroll.jumpTo(-900);
    await tester.pump();
    final lines = find.byType(RichText);
    final from = tester.getTopLeft(lines.at(1)) + const Offset(3, 4);
    final to = tester.getTopLeft(lines.at(3)) + const Offset(20, 4);
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await g.moveTo(from + const Offset(10, 0));
    await g.moveTo(to);
    await tester.pump();
    final sel = doc.selection;
    expect(sel.isCollapsed, isFalse);
    expect(sel.end, lessThan(s.buffer.lineStart(before)), reason: 'all on static lines above the window');
    await g.up();
    await tester.pump();
    await tester.pump();
    expect(doc.selection, sel);
    expect(s.window.windowStart, lessThanOrEqualTo(sel.start), reason: 'the window now holds the selection');
    expect(s.window.selection, TextSelection(baseOffset: sel.baseOffset - s.window.windowStart, extentOffset: sel.extentOffset - s.window.windowStart));
    _expectCoherent(s, doc, text);
  });

  testWidgets('shift-click on a static line extends the selection from the caret', (tester) async {
    final text = generateManuscript(12000, seed: 16);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    final int caret = doc.selection.baseOffset;
    s.scroll.jumpTo(-600);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tapAt(tester.getTopLeft(find.byType(RichText).first) + const Offset(2, 2), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    await tester.pump();
    expect(doc.selection.baseOffset, caret);
    expect(doc.selection.extentOffset, lessThan(caret));
    _expectCoherent(s, doc, text);
  });

  testWidgets('double click on a static line selects the word', (tester) async {
    final text = generateManuscript(12000, seed: 17);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    s.scroll.jumpTo(-600);
    await tester.pump();
    final at = tester.getTopLeft(find.byType(RichText).first) + const Offset(12, 6);
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump();
    final sel = doc.selection;
    expect(sel.isCollapsed, isFalse, reason: '$sel');
    final word = text.substring(sel.start, sel.end);
    expect(word.contains(' '), isFalse, reason: word);
    expect(word.isNotEmpty, isTrue);
  });
}
