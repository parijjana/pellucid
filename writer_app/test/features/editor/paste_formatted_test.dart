// Description: Pasting formatted text (backlog item 22): HTML on the clipboard
// becomes Markdown, plain text stays plain, Pellucid's own markdown wins, and
// Cmd/Ctrl+Shift+V pastes plain text only.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/marker_aware_editing.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/rich_clipboard.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MarkdownEditingController c;
  String? html, markdown, plain;
  const channel = MethodChannel('com.overengineeredhobbies.pellucid/clipboard');

  setUp(() {
    html = markdown = plain = null;
    RichClipboard.debugSupported = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getHtml') return html;
      if (call.method == 'getMarkdown') return markdown;
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return plain == null ? null : <String, dynamic>{'text': plain};
      }
      return null;
    });
  });
  tearDown(() {
    RichClipboard.debugSupported = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('iOS reads HTML and Pellucid markdown through the channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      expect(RichClipboard.isSupportedOn(defaultTargetPlatform), isTrue);
      html = '<p>hi <b>there</b></p>';
      markdown = 'hi **there**';
      expect(await RichClipboard.readHtml(), html);
      expect(await RichClipboard.readMarkdown(), markdown);
      html = null;
      expect(await RichClipboard.readHtml(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('Windows and Android are not gated in for rich reads', () {
    expect(RichClipboard.isSupportedOn(TargetPlatform.windows), isFalse);
    expect(RichClipboard.isSupportedOn(TargetPlatform.android), isFalse);
  });

  /// Runs [body] with the platform overridden and restored before the test ends.
  void paste(
    String name,
    TargetPlatform platform,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> pumpEditor(
    WidgetTester tester, {
    String text = 'start: ',
  }) async {
    c = MarkdownEditingController(text: text, theme: WriterTheme.presets[0]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkerAwareEditing(
            controller: c,
            child: TextField(controller: c, autofocus: true, maxLines: null),
          ),
        ),
      ),
    );
    await tester.pump();
    c.selection = TextSelection.collapsed(offset: text.length);
    await tester.pump();
  }

  Future<void> chord(WidgetTester tester, {bool shift = false}) async {
    final mod = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(mod);
    await tester.pumpAndSettle();
  }

  paste(
    'formatted HTML pastes as Markdown (Word-style list, bold, heading)',
    TargetPlatform.macOS,
    (tester) async {
      html =
          '<h2>Title</h2><p>Some <b style="color:red">bold</b> text</p><ul><li>one</li><li>two</li></ul>';
      plain = 'Title\nSome bold text\none\ntwo';
      await pumpEditor(tester);
      await chord(tester);
      expect(c.text, 'start: ## Title\nSome **bold** text\n- one\n- two');
    },
  );

  paste(
    'HTML that adds nothing over the plain text pastes the plain text exactly',
    TargetPlatform.macOS,
    (tester) async {
      html = '<div style="font-family:Menlo">  indented()</div>';
      plain = '  indented()';
      await pumpEditor(tester);
      await chord(tester);
      expect(c.text, 'start:   indented()');
    },
  );

  paste('plain text only: pastes plain', TargetPlatform.macOS, (tester) async {
    plain = '**not converted** # nor this';
    await pumpEditor(tester);
    await chord(tester);
    expect(c.text, 'start: **not converted** # nor this');
  });

  paste("Pellucid's own markdown wins over HTML", TargetPlatform.macOS, (
    tester,
  ) async {
    markdown = 'own **md**';
    html = '<p>own <i>md</i></p>';
    plain = 'own md';
    await pumpEditor(tester);
    await chord(tester);
    expect(c.text, 'start: own **md**');
  });

  paste(
    'Cmd+Shift+V pastes plain text even when HTML and markdown are present',
    TargetPlatform.macOS,
    (tester) async {
      markdown = 'own **md**';
      html = '<p>a <b>b</b></p>';
      plain = 'a b';
      await pumpEditor(tester);
      await chord(tester, shift: true);
      expect(c.text, 'start: a b');
    },
  );

  paste(
    'Ctrl+Shift+V on Windows pastes plain text; Ctrl+V converts',
    TargetPlatform.windows,
    (tester) async {
      html = '<p>a <b>b</b></p>';
      plain = 'a b';
      await pumpEditor(tester);
      await chord(tester, shift: true);
      expect(c.text, 'start: a b');
      await chord(tester);
      expect(c.text, 'start: a ba **b**');
    },
  );

  paste('context menu offers Paste as plain text', TargetPlatform.macOS, (
    tester,
  ) async {
    html = '<p>x <b>y</b></p>';
    plain = 'x y';
    await pumpEditor(tester);
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    final item = MarkerAwareEditing.pastePlainItem(state)!;
    expect(item.label, 'Paste as plain text');
    item.onPressed!();
    await tester.pumpAndSettle();
    expect(c.text, 'start: x y');
  });
}
