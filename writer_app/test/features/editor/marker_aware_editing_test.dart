// Description: The hidden-marker rules wired into a real TextField: arrow keys,
// Backspace, typing, clicks and copy/paste (backlog item 24).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/marker_aware_editing.dart';
import 'package:pellucid/features/editor/marker_edit_rules.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/rich_clipboard.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

void main() {
  late MarkdownEditingController c;

  Future<void> pumpEditor(WidgetTester tester, String text, int caret) async {
    c = MarkdownEditingController(text: text, theme: WriterTheme.presets[0]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarkerAwareEditing(
          controller: c,
          child: TextField(
            controller: c,
            autofocus: true,
            maxLines: null,
            inputFormatters: const [MarkerEditFormatter()],
          ),
        ),
      ),
    ));
    await tester.pump();
    c.selection = TextSelection.collapsed(offset: caret);
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(k);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    group('on ${platform.name}', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      testWidgets('Right arrow crosses hidden markers in one press', (tester) async {
        await pumpEditor(tester, 'a**bold** end', 1);
        await key(tester, LogicalKeyboardKey.arrowRight);
        expect(c.selection.baseOffset, 4);
        await key(tester, LogicalKeyboardKey.arrowLeft);
        expect(c.selection.baseOffset, 1);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('Shift+Right extends over markers too', (tester) async {
        await pumpEditor(tester, 'a**bold** end', 0);
        await key(tester, LogicalKeyboardKey.arrowRight, shift: true);
        await key(tester, LogicalKeyboardKey.arrowRight, shift: true);
        expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 4));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('Backspace after a heading prefix makes the line body text', (tester) async {
        await pumpEditor(tester, 'ab\n# Head', 5);
        await key(tester, LogicalKeyboardKey.backspace);
        expect(c.text, 'ab\nHead');
        await key(tester, LogicalKeyboardKey.backspace);
        expect(c.text, 'abHead');
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('deleting the last bold letter leaves no stray markers; undo restores it', (tester) async {
        await pumpEditor(tester, 'a**b** c', 4);
        await tester.pump(const Duration(milliseconds: 600));
        await key(tester, LogicalKeyboardKey.backspace);
        expect(c.text, 'a c');
        // UndoHistory throttles pushes; let the baseline and the edit land.
        await tester.pump(const Duration(milliseconds: 600));
        final mod = platform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(mod);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(mod);
        await tester.pump();
        expect(c.text, 'a**b** c');
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }

  testWidgets('a caret placed inside markers rests at the run edge', (tester) async {
    await pumpEditor(tester, 'a**bold**', 0);
    c.selection = const TextSelection.collapsed(offset: 2);
    expect(c.selection.baseOffset, 1);
    c.selection = const TextSelection.collapsed(offset: 8);
    expect(c.selection.baseOffset, 7);
  });

  testWidgets('typing at the end of a bold run continues it, at its start does not', (tester) async {
    await pumpEditor(tester, 'a**bold** z', 8);
    expect(c.selection.baseOffset, 7);
    tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'a**boldX** z', selection: TextSelection.collapsed(offset: 8)));
    await tester.pump();
    expect(c.text, 'a**boldX** z');
    c.selection = const TextSelection.collapsed(offset: 3);
    expect(c.selection.baseOffset, 1);
  });

  testWidgets('toggling bold off with a collapsed caret ends the run there', (tester) async {
    await pumpEditor(tester, '**ab**', 4);
    c.toggleFormat('**');
    expect(c.selection.baseOffset, 6);
    tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '**ab**x', selection: TextSelection.collapsed(offset: 7)));
    await tester.pump();
    expect(c.text, '**ab**x');
  });

  testWidgets('toggling bold on then moving away leaves no empty markers', (tester) async {
    await pumpEditor(tester, 'ab cd', 2);
    c.toggleFormat('**');
    expect(c.text, 'ab**** cd');
    expect(c.selection.baseOffset, 4);
    c.selection = const TextSelection.collapsed(offset: 9);
    expect(c.text, 'ab cd');
    expect(c.selection.baseOffset, 5);
  });

  test('rich copy has a native side on macOS and iOS only', () {
    expect(RichClipboard.isSupportedOn(TargetPlatform.macOS), isTrue);
    expect(RichClipboard.isSupportedOn(TargetPlatform.iOS), isTrue);
    expect(RichClipboard.isSupportedOn(TargetPlatform.windows), isFalse); // C++ draft not built yet
    expect(RichClipboard.isSupportedOn(TargetPlatform.android), isFalse);
  });

  group('copy and paste', () {
    final calls = <MethodCall>[];
    String? pasteboardMarkdown;

    setUp(() {
      calls.clear();
      pasteboardMarkdown = null;
      RichClipboard.debugSupported = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.overengineeredhobbies.pellucid/clipboard'),
        (call) async {
          calls.add(call);
          if (call.method == 'setRich') pasteboardMarkdown = (call.arguments as Map)['markdown'] as String;
          if (call.method == 'getMarkdown') return pasteboardMarkdown;
          return null;
        },
      );
    });
    tearDown(() {
      RichClipboard.debugSupported = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.overengineeredhobbies.pellucid/clipboard'), null);
    });

    testWidgets('copy sends HTML, plain text and markdown; paste in Pellucid gets the markdown', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pumpEditor(tester, 'x **bold** y', 0);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 7); // "x **bol"
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      final args = calls.single.arguments as Map;
      expect(args['plain'], 'x bol');
      expect(args['html'], '<p>x <strong>bol</strong></p>');
      expect(args['markdown'], 'x **bol**');

      c.selection = TextSelection.collapsed(offset: c.text.length);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(c.text, 'x **bold** yx **bol**');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('cut removes the selection with markers kept balanced', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pumpEditor(tester, 'ab**cd**ef', 0);
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 5); // "b**c"
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(c.text, 'a**d**ef');
      expect((calls.single.arguments as Map)['markdown'], 'b**c**');
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('copy formats', () {
    test('headings, bullets and nested runs', () {
      const t = '# Title\n- item\n**<u>bu</u>** *i*';
      expect(plainTextFor(t, 0, t.length), 'Title\n• item\nbu i');
      expect(htmlFor(t, 0, t.length),
          '<h1>Title</h1><ul><li>item</li></ul><p><strong><u>bu</u></strong> <em>i</em></p>');
      expect(markdownFor(t, 0, t.length), '# Title\n- item\n**<u>bu</u>** *i*');
    });
    test('html is escaped', () {
      expect(htmlFor('a < b & "c"', 0, 11), '<p>a &lt; b &amp; &quot;c&quot;</p>');
    });
    test('a range starting mid-heading drops the prefix', () {
      expect(markdownFor('# Title', 4, 7), 'tle');
    });
  });
}
