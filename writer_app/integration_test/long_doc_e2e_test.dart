// Long-document (windowed editor) end-to-end suite. See tool/e2e/run_long_doc.sh,
// which builds this under an isolated bundle id and guards the owner's data.
// Check numbers follow the owner's manual list ("step 6: big manuscript").

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';

import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  check('Check 0: setup - 127k-word manuscript opens in the windowed editor', (tester) async {
    final rig = await mount(tester);
    rig.expectWindowed();
    expect(rig.fx.words, greaterThan(120000));
    expect(rig.text == rig.fx.text, isTrue);
    final w = rig.win;
    // ignore: avoid_print
    print('EVID|setup|words=${rig.fx.words} chars=${rig.text.length} lines=${w.buffer.lineCount} '
        'windowChars=${w.window.text.length} threshold=$kWindowedEditorMinWords words');
    expect(w.window.text.length, lessThan(rig.text.length ~/ 20), reason: 'only a window is live');
    await rig.dispose();
  });

  // ------------------------------------------------------------- Check 3 ---
  check('Check 3: type, undo/redo, click far away, undo brings the right text back', (tester) async {
    final rig = await mount(tester);
    final orig = rig.text;
    final fx = rig.fx;
    final at = fx.lineStart(fx.boldLine) + 2;
    await rig.reveal(at);
    await rig.placeCaret(at);
    await rig.typeText('hello brave world');
    final typed = orig.replaceRange(at, at, 'hello brave world');
    rig.expectDoc(typed, 'document');
    await rig.key(LogicalKeyboardKey.keyZ, meta: true);
    rig.expectDoc(orig, 'one undo removes the typed run');
    await rig.key(LogicalKeyboardKey.keyZ, meta: true, shift: true);
    rig.expectDoc(typed, 'redo puts it back');

    // Click far away: chapter 40's heading line.
    final farLine = fx.chapterLines[39];
    await rig.reveal(fx.lineStart(farLine));
    final before = rig.sel;
    await rig.tester.tapAt(rig.pointInLine(farLine, dx: 60), kind: PointerDeviceKind.mouse);
    await rig.pump(4);
    final ls = fx.lineStart(farLine) + (typed.length - orig.length);
    expect(rig.sel.isCollapsed, isTrue);
    expect(rig.sel.baseOffset, inInclusiveRange(ls, ls + fx.lines[farLine].length),
        reason: 'caret moved to the clicked line (was $before)');
    rig.expectDoc(typed, 'document');

    await rig.key(LogicalKeyboardKey.keyZ, meta: true);
    rig.expectDoc(orig, 'undo after a far click removes the typed words, nothing else');
    // ignore: avoid_print
    print('EVID|3|after far undo caret=${rig.sel.baseOffset} (edit was at $at)');
    await rig.key(LogicalKeyboardKey.keyZ, meta: true, shift: true);
    rig.expectDoc(typed, 'document');
    await rig.dispose();
  });

  // ------------------------------------------------------------- Check 4 ---
  check('Check 4: accent composing + emoji while the caret moves down the page', (tester) async {
    final rig = await mount(tester);
    final orig = rig.text;
    final fx = rig.fx;
    final start = fx.lineStart(fx.chapterLines[14]) + 40;
    await rig.reveal(start);
    await rig.placeCaret(start);
    final inserts = <(int, String)>[];
    for (int round = 0; round < 4; round++) {
      // The caret walks down the page with the arrow keys between insertions.
      for (int i = 0; i < 6; i++) {
        await rig.key(LogicalKeyboardKey.arrowDown);
      }
      final String wtext = rig.win.window.text;
      final int c = rig.win.window.selection.baseOffset;
      final int docAt = rig.win.window.windowStart + c;
      expect(rig.sel.baseOffset, docAt);
      // Accent being composed: the dead-key accent, then committed as e-acute.
      rig.tester.testTextInput.updateEditingValue(TextEditingValue(
        text: wtext.replaceRange(c, c, '´'),
        selection: TextSelection.collapsed(offset: c + 1),
        composing: TextRange(start: c, end: c + 1),
      ));
      await rig.pump(3);
      expect(rig.win.window.value.composing.isValid, isTrue, reason: 'composing held');
      rig.tester.testTextInput.updateEditingValue(TextEditingValue(
        text: wtext.replaceRange(c, c, 'é'),
        selection: TextSelection.collapsed(offset: c + 1),
      ));
      await rig.pump(4);
      inserts.add((docAt, 'é'));
      // Emoji (surrogate pair) at the new caret.
      final String w2 = rig.win.window.text;
      final int c2 = rig.win.window.selection.baseOffset;
      final int docAt2 = rig.win.window.windowStart + c2;
      rig.tester.testTextInput.updateEditingValue(TextEditingValue(
        text: w2.replaceRange(c2, c2, '😀'),
        selection: TextSelection.collapsed(offset: c2 + 2),
      ));
      await rig.pump(4);
      inserts.add((docAt2, '😀'));
    }
    var expected = orig;
    for (final (off, s) in inserts.reversed) {
      expected = expected.replaceRange(off, off, s);
    }
    rig.expectDoc(expected, '4 accents and 4 emoji landed exactly where the caret was');
    expect(rig.text.length, orig.length + 4 + 8);
    await rig.dispose();
  });

  // ------------------------------------------------------------- Check 5 ---
  check('Check 5: triple-click on a far line selects that line', (tester) async {
    final rig = await mount(tester);
    final fx = rig.fx;
    final line = fx.darcyLine;
    final ls = fx.lineStart(line);
    final le = ls + fx.lines[line].length;
    await rig.reveal(ls);
    final p = rig.pointInLine(line, dx: 60);
    for (int i = 0; i < 3; i++) {
      await rig.tester.tapAt(p, kind: PointerDeviceKind.mouse);
      await rig.tester.pump(const Duration(milliseconds: 40));
    }
    await rig.pump(4);
    final sel = rig.sel;
    expect(sel.start, ls, reason: 'selection starts at the line start: $sel');
    expect(sel.end, inInclusiveRange(le, le + 1), reason: 'and ends at the line end (or its newline): $sel');
    expect(rig.text.substring(sel.start, le), fx.lines[line]);
    await rig.dispose();
  });

  // ------------------------------------------------------------- Check 6 ---
  check('Check 6: shift-click far below the caret, then Shift+Down grows the selection', (tester) async {
    final rig = await mount(tester);
    final fx = rig.fx;
    final a = fx.lineStart(fx.chapterLines[19]) + 30;
    await rig.reveal(a);
    await rig.placeCaret(a);
    final lineB = fx.chapterLines[22];
    await rig.reveal(fx.lineStart(lineB));
    await rig.tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await rig.tester.tapAt(rig.pointInLine(lineB, dx: 120), kind: PointerDeviceKind.mouse);
    await rig.tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await rig.pump(5);
    final s1 = rig.sel;
    expect(s1.baseOffset, a, reason: 'anchor stays at the caret');
    final bs = fx.lineStart(lineB);
    expect(s1.extentOffset, inInclusiveRange(bs, bs + fx.lines[lineB].length));
    await rig.key(LogicalKeyboardKey.arrowDown, shift: true);
    final s2 = rig.sel;
    expect(s2.baseOffset, a, reason: 'anchor unchanged by Shift+Down: $s2');
    expect(s2.extentOffset, greaterThan(s1.extentOffset), reason: 'extent grew from the shift-click point');
    // ignore: avoid_print
    print('EVID|6|anchor=$a shiftClick extent=${s1.extentOffset} afterShiftDown=${s2.extentOffset}');
    await rig.dispose();
  });

  // ------------------------------------------------------------- Check 8 ---
  check('Check 8: Cmd+B and Cut act on the whole long selection', (tester) async {
    final rig = await mount(tester);
    final fx = rig.fx;
    final orig = rig.text;
    final s = fx.lineStart(fx.chapterLines[18]) + 10;
    final e = s + 30000;
    await rig.reveal(s);
    await rig.placeCaret(s);
    rig.doc.selection = TextSelection(baseOffset: s, extentOffset: e);
    await rig.pump(5);
    await rig.key(LogicalKeyboardKey.keyB, meta: true);
    final bolded = rig.text;
    expect(bolded.length, orig.length + 4, reason: 'one ** pair around the whole stretch');
    expect(bolded.substring(s, s + 2), '**');
    expect(bolded.substring(e + 2, e + 4), '**');
    expect(bolded.replaceRange(e + 2, e + 4, '').replaceRange(s, s + 2, ''), orig);

    await rig.key(LogicalKeyboardKey.keyZ, meta: true);
    rig.expectDoc(orig, 'undo restores the document');
    rig.doc.selection = TextSelection(baseOffset: s, extentOffset: e);
    await rig.pump(5);
    await rig.key(LogicalKeyboardKey.keyX, meta: true);
    rig.expectDoc(orig.replaceRange(s, e, ''), 'cut removed exactly the selection');
    final clip = await rig.readClipboard();
    expect(clip, orig.substring(s, e), reason: 'the clipboard holds all 30000 characters');
    await rig.dispose();
  });

  // ------------------------------------------------------------ Check 11 ---
  check('Check 11: far bullet list - Enter, undo-after-Enter, Tab, Backspace', (tester) async {
    final rig = await mount(tester);
    final fx = rig.fx;
    final orig = rig.text;
    final l2 = fx.bulletFirstLine + 1; // "- Second item"
    final end2 = fx.lineStart(l2) + fx.lines[l2].length;
    await rig.reveal(end2);
    await rig.placeCaret(end2);
    // Enter continues the list with a marker.
    await rig.typeText('\n');
    final withMarker = orig.replaceRange(end2, end2, '\n- ');
    rig.expectDoc(withMarker, 'Enter adds the next bullet');
    expect(rig.sel.baseOffset, end2 + 3);
    // Undo straight after Enter removes only the marker.
    await rig.key(LogicalKeyboardKey.keyZ, meta: true);
    rig.expectDoc(orig.replaceRange(end2, end2, '\n'), 'undo removes only the auto marker');
    // Put the marker back by typing it, as the writer would.
    await rig.typeText('- ');
    rig.expectDoc(withMarker, 'document');
    // Tab on the empty item indents it.
    await rig.key(LogicalKeyboardKey.tab);
    final nl = rig.text.indexOf('\n', end2 + 1);
    final newLine = rig.text.substring(end2 + 1, nl == -1 ? null : nl);
    expect(newLine.startsWith(' '), isTrue, reason: 'indented: "$newLine"');
    expect(newLine.trimLeft().startsWith('-'), isTrue);
    // Backspace right after the marker removes the style.
    await rig.key(LogicalKeyboardKey.backspace);
    // ignore: avoid_print
    print('EVID|11|after Tab line="$newLine"; text after Backspace around caret='
        '${rig.text.substring(end2, end2 + 14).replaceAll('\n', r'\n')}');
    expect(rig.text.length, lessThan(withMarker.length + 4));
    expect(rig.text.substring(0, end2), orig.substring(0, end2));
    expect(rig.text.substring(rig.text.length - (orig.length - end2)), orig.substring(end2),
        reason: 'the rest of the document is untouched');
    await rig.dispose();
  });

  // ------------------------------------------------------------ Check 12 ---
  check('Check 12: far heading and bold lines show text without # / ** markers', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = await mount(tester);
    final fx = rig.fx;
    Future<void> expectClean(int line) async {
      await rig.reveal(fx.lineStart(line));
      final raw = fx.lines[line];
      final visible = visibleText(raw);
      expect(visible, isNot(contains('**')));
      expect(visible.startsWith('#'), isFalse);
      // 1. Semantics label (what a reader announces).
      expect(find.bySemanticsLabel(visible), findsWidgets, reason: 'semantics label "$visible"');
      // 2. Rendered spans: every marker character is in a hidden (transparent, 1px) span.
      final rt = rig.tester
          .widget<RichText>(find.descendant(of: find.byKey(ValueKey('L$line')), matching: find.byType(RichText)));
      final shown = StringBuffer();
      final hidden = StringBuffer();
      rt.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          final st = span.style;
          final isHidden = st != null && st.color == Colors.transparent && st.fontSize == 1.0;
          (isHidden ? hidden : shown).write(span.text);
        }
        return true;
      });
      expect(shown.toString().trim(), visible.trim(), reason: 'visible spans of "$raw"');
      expect(hidden.toString().contains('#') || hidden.toString().contains('**'), isTrue,
          reason: 'the markers are there but hidden');
    }

    await expectClean(fx.headingLine);
    await expectClean(fx.boldLine);
    handle.dispose();
    await rig.dispose();
  });
}
