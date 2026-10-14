// Owner checklist: paste (L154, L173, L195, L197, L199). HTML fixtures in test/fixtures/ are real-world
// shaped (Chrome list copy, Word and Google Docs paragraph copy, VS Code copy). They go in through the
// mocked native rich-pasteboard channel (`getHtml`); the system clipboard is the in-memory mock too.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/rich_clipboard.dart';
import 'package:pellucid/features/editor/marker_aware_editing.dart' show PastePlainTextIntent;

import '../support/editor_helpers.dart';
import '../support/harness.dart';

const _fixtureDir = String.fromEnvironment('E2E_FIXTURES');

String fixtureHtml(String name) {
  expect(_fixtureDir, isNotEmpty, reason: 'run through tool/e2e/run_*.sh (it passes --dart-define=E2E_FIXTURES)');
  return File('$_fixtureDir/$name').readAsStringSync();
}

const em = ' ';

Future<void> _paste(Rig rig) async {
  await rig.key(LogicalKeyboardKey.keyV, meta: true);
  await rig.wait(const Duration(milliseconds: 500));
}

void registerPasteChecks() {
  check('Check L154: a nested list pasted from a web page keeps 4-space nesting', (tester) async {
    final rig = await mount(tester, text: 'Before\n');
    await rig.setExternalClipboard('Fruit\n\tApple\n\tBanana\n\t\tPlantain\nVegetables', html: fixtureHtml('web_nested_list.html'));
    await rig.placeCaret(rig.text.length);
    await _paste(rig);
    rig.expectDoc('Before\n- Fruit\n    - Apple\n    - Banana\n        - Plantain\n- Vegetables', 'nested list lands with 4-space nesting');
    await rig.dispose();
  });

  const wordText = 'An indented paragraph from Word.\nAnother one, indented in inches.\nA hanging indent paragraph.\nA plain paragraph.';

  check('Check L173a: Word paragraph with a left indent (36.0pt) lands indented', (tester) async {
    final rig = await mount(tester, text: '');
    await rig.setExternalClipboard(wordText, html: fixtureHtml('word_indented_paragraph.html'));
    await rig.placeCaret(0);
    await _paste(rig);
    final lines = rig.text.split('\n');
    // ignore: avoid_print
    print('EVID|L173|Word paste lines: ${lines.map((l) => l.replaceAll(em, '<em>')).toList()}');
    expect(lines[0], '${em}An **indented** paragraph from Word.', reason: 'margin-left:36.0pt lands as one indent level');
    expect(lines.last, 'A plain **paragraph**.');
    await rig.dispose();
  });

  check('Check L173b: Word ".5in" margin lands indented', (tester) async {
    final rig = await mount(tester, text: '');
    await rig.setExternalClipboard(wordText, html: fixtureHtml('word_indented_paragraph.html'));
    await rig.placeCaret(0);
    await _paste(rig);
    expect(rig.text.split('\n')[1], '${em}Another one, **indented** in inches.', reason: 'Word writes margin-left:.5in without a leading zero');
    await rig.dispose();
  }, knownBug: 'html_to_markdown.dart:333 - _indentLevel regex needs a leading digit, so Word ".5in" (no leading zero) is dropped, not indented');

  check('Check L173c: a hanging indent from Word (36pt / -18pt) lands plain', (tester) async {
    final rig = await mount(tester, text: '');
    await rig.setExternalClipboard(wordText, html: fixtureHtml('word_indented_paragraph.html'));
    await rig.placeCaret(0);
    await _paste(rig);
    expect(rig.text.split('\n')[2], 'A **hanging** indent paragraph.', reason: 'hanging (margin-left + negative text-indent) is not a plain indent');
    await rig.dispose();
  }, knownBug: 'html_to_markdown.dart:316-319 - margin-left is applied as an indent without looking at a negative text-indent, so a hanging indent (margin-left:36pt; text-indent:-18pt) lands indented instead of plain');

  check('Check L173e: a pure indent paste (no other formatting) from Word still lands indented', (tester) async {
    final rig = await mount(tester, text: '');
    await rig.setExternalClipboard('An indented paragraph from Word.', html: fixtureHtml('word_indent_only.html'));
    await rig.placeCaret(0);
    await _paste(rig);
    expect(rig.text, '${em}An indented paragraph from Word.', reason: 'only an indent: still pasted indented');
    await rig.dispose();
  }, knownBug: 'html_to_markdown.dart:25-29 - htmlAddsStructure squashes all whitespace (\\s matches the U+2003 indent), so an indent-only paste counts as "no structure" and falls back to the plain paste');

  check('Check L173d: Google Docs indented paragraph lands indented, hanging lands plain, no stray bold', (tester) async {
    final rig = await mount(tester, text: '');
    await rig.setExternalClipboard('An indented paragraph from Docs.\n\nA hanging indent paragraph from Docs.', html: fixtureHtml('gdocs_indented_paragraph.html'));
    await rig.placeCaret(0);
    await _paste(rig);
    final lines = rig.text.split('\n');
    // ignore: avoid_print
    print('EVID|L173|Docs paste lines: ${lines.map((l) => l.replaceAll(em, '<em>')).toList()}');
    expect(lines.first, '${em}An indented paragraph from **Docs**.', reason: 'only the <span font-weight:700> is bold, not the font-weight:normal <b> wrapper');
    await rig.dispose();
  });

  check('Check L173f: a Google Docs hanging indent lands plain', (tester) async {
    final rig = await mount(tester, text: '');
    await rig.setExternalClipboard('An indented paragraph from Docs.\n\nA hanging indent paragraph from Docs.', html: fixtureHtml('gdocs_indented_paragraph.html'));
    await rig.placeCaret(0);
    await _paste(rig);
    expect(rig.text.split('\n').last, 'A hanging indent paragraph from Docs.', reason: 'hanging indent lands plain');
    await rig.dispose();
  }, knownBug: 'html_to_markdown.dart:316-319 - same as L173c: margin-left:36pt with text-indent:-18pt (Docs hanging indent) is applied as a plain left indent');

  check('Check L195: bold-italic with underline pasted from Word renders as bold, italic and underlined', (tester) async {
    final rig = await mount(tester, text: '');
    await rig.setExternalClipboard('Bold italic underlined then plain bold italic.', html: fixtureHtml('word_bold_italic_underline.html'));
    await rig.placeCaret(0);
    await _paste(rig);
    // ignore: avoid_print
    print('EVID|L195|markdown landed as: ${rig.text}');
    expect(visibleText(rig.text), 'Bold italic underlined then plain bold italic.', reason: 'no marker junk in the visible text');
    final line = scanLineAt(rig.text, 0);
    bool has(int at, bool Function(InlineRun r) f) => line.runs.any((r) => r.contentStart <= at && at < r.contentEnd && f(r));
    final u = rig.text.indexOf('underlined'), p = rig.text.indexOf('plain bold');
    expect(has(u, (r) => r.bold), isTrue, reason: 'underlined words are bold');
    expect(has(u, (r) => r.italic), isTrue, reason: 'underlined words are italic');
    expect(has(u, (r) => r.underline), isTrue, reason: 'underlined words are underlined');
    expect(has(p, (r) => r.bold) && has(p, (r) => r.italic), isTrue, reason: 'second phrase is bold italic');
    expect(has(p, (r) => r.underline), isFalse, reason: 'second phrase is not underlined');
    // The spans really render with those styles.
    final spans = leafSpans(rig).where((s) => (s.text ?? '').contains('underlined')).toList();
    expect(spans, isNotEmpty);
    final st = spans.first.style!;
    expect(st.fontWeight, FontWeight.bold);
    expect(st.fontStyle, FontStyle.italic);
    expect(st.decoration?.contains(TextDecoration.underline), isTrue);
    await rig.dispose();
  });

  check('Check L197: Cmd+Shift+V, the Edit menu item and right-click paste as plain text', (tester) async {
    const plain = 'Fruit\n\tApple\nVegetables';
    final rig = await mount(tester, text: 'Start ');
    await rig.setExternalClipboard(plain, html: fixtureHtml('web_nested_list.html'));
    // Control: normal paste converts.
    await rig.placeCaret(6);
    await _paste(rig);
    await rig.wait(const Duration(milliseconds: 800));
    // ignore: avoid_print
    print('EVID|L197|control Cmd+V result: ${rig.text.replaceAll('\n', r'\n')} (rich clipboard supported=${RichClipboard.isSupported}, html=${externalHtml != null})');
    expect(rig.text, startsWith('Start - Fruit'), reason: 'plain Cmd+V converts the HTML (control): "${rig.text}"');
    rig.doc.value = const TextEditingValue(text: 'Start ', selection: TextSelection.collapsed(offset: 6));

    // 1. Cmd+Shift+V.
    await rig.placeCaret(6);
    await rig.key(LogicalKeyboardKey.keyV, meta: true, shift: true);
    await rig.wait(const Duration(milliseconds: 500));
    rig.expectDoc('Start $plain', 'Cmd+Shift+V pastes the clipboard text as is');
    rig.doc.value = const TextEditingValue(text: 'Start ', selection: TextSelection.collapsed(offset: 6));

    // 2. The Edit menu item: PastePlainTextIntent on the focused node (what the menu bar does).
    await rig.placeCaret(6);
    final ctx = FocusManager.instance.primaryFocus!.context!;
    Actions.invoke(ctx, const PastePlainTextIntent());
    await rig.wait(const Duration(milliseconds: 500));
    rig.expectDoc('Start $plain', 'Edit > Paste as Plain Text pastes as is');
    rig.doc.value = const TextEditingValue(text: 'Start ', selection: TextSelection.collapsed(offset: 6));

    // 3. Right-click > Paste as plain text.
    await rig.placeCaret(6);
    final p = await pointAt(rig, 2);
    await tester.tapAt(p, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await rig.wait(const Duration(milliseconds: 800));
    expect(find.text('Paste as plain text'), findsOneWidget, reason: 'the context menu offers it');
    expect(find.text('Paste'), findsOneWidget);
    await tester.tap(find.text('Paste as plain text'));
    await rig.wait(const Duration(milliseconds: 600));
    expect(rig.text, contains(plain), reason: 'right-click paste as plain text pastes as is: "${rig.text}"');
    expect(rig.text, isNot(contains('- Fruit')));
    await rig.dispose();
  });

  check('Check L199: code pasted from a code editor is unchanged', (tester) async {
    const code = 'function add(a, b) {\n    return a + b; // *sum* of __two__\n}';
    final rig = await mount(tester, text: '');
    await rig.setExternalClipboard(code, html: fixtureHtml('code_editor_paste.html'));
    await rig.placeCaret(0);
    await _paste(rig);
    rig.expectDoc(code, 'code (indentation, asterisks, underscores) lands exactly as copied');
    await rig.dispose();
  });
}
