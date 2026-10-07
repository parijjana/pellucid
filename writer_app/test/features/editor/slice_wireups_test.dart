// Description: Behaviour that only exists once the 1.1.0 slices meet in the
// integration branch (slice 4 marker editing/rich copy, slice 6 formats,
// slice 7 context menu, slice 8 grammar hints and smart punctuation).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/rich_clipboard.dart';
import 'package:pellucid/features/editor/marker_aware_editing.dart';
import 'package:pellucid/features/editor/widgets/editor_context_menu.dart';
import 'package:pellucid/features/editor/widgets/editor_selection_actions.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/editor/utils/grammar_checker.dart';

const _channel = MethodChannel('com.overengineeredhobbies.pellucid/clipboard');

void main() {
  final macOnly = TargetPlatformVariant.only(TargetPlatform.macOS);

  group('rich copy reaches slice 7 (context menu, Add to note/attributions)', () {
    final rich = <Map>[];
    setUp(() {
      rich.clear();
      RichClipboard.debugSupported = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel,
          (call) async {
        if (call.method == 'setRich') rich.add(call.arguments as Map);
        return null;
      });
    });
    tearDown(() {
      RichClipboard.debugSupported = null;
      ActiveEditor.controller = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    });

    testWidgets('editor menu Copy goes through the marker-aware rich copy', (tester) async {
      final c = MarkdownEditingController(text: 'x **bold** y', theme: WriterTheme.presets.first);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkerAwareEditing(
            controller: c,
            child: TextField(
              controller: c,
              maxLines: null,
              contextMenuBuilder: (ctx, s) => buildEditorContextMenu(ctx, s),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 10);
      await tester.pump();
      tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
      await tester.pump();
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(rich, hasLength(1));
      expect(rich.single['plain'], 'x bold');
      expect(rich.single['markdown'], 'x **bold**');
      expect(rich.single['html'], contains('<strong>bold</strong>'));
    }, variant: macOnly);

    test('Add-to-note copy uses the live selection, closing a cut run', () async {
      final c = MarkdownEditingController(text: 'x **bold** y', theme: WriterTheme.presets.first);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 7); // "x **bol"
      ActiveEditor.controller = c;
      await EditorSelectionActions.copySelection('x **bol');
      expect(rich.single['plain'], 'x bol');
      expect(rich.single['markdown'], 'x **bol**');
    });

    test('Add-to-note copy without a live editor still copies rich text', () async {
      await EditorSelectionActions.copySelection('plain words');
      expect(rich.single['plain'], 'plain words');
    });
  });

  group('slice 8 grammar fix in slice 7 menu', () {
    Future<MarkdownEditingController> openMenuAt(WidgetTester tester, String text, int caret) async {
      final c = MarkdownEditingController(text: text, theme: WriterTheme.presets.first);
      c.setGrammarIssues(GrammarChecker.check(text));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: c,
            maxLines: null,
            contextMenuBuilder: (ctx, s) => buildEditorContextMenu(ctx, s),
          ),
        ),
      ));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      c.selection = TextSelection.collapsed(offset: caret);
      await tester.pump();
      tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
      await tester.pump();
      return c;
    }

    testWidgets('lone i offers and applies the capital I', (tester) async {
      final c = await openMenuAt(tester, 'so i went', 4);
      await tester.tap(find.text('Use “I”'));
      await tester.pump();
      expect(c.text, 'so I went');
    }, variant: macOnly);

    testWidgets('repeated word offers removal', (tester) async {
      final c = await openMenuAt(tester, 'saw the the cat', 11);
      await tester.tap(find.text('Remove repeated word'));
      await tester.pump();
      expect(c.text, 'saw the cat');
    }, variant: macOnly);

    testWidgets('no hint under the caret, no grammar item', (tester) async {
      await openMenuAt(tester, 'so I went', 8);
      expect(find.textContaining('Use “'), findsNothing);
      expect(find.text('Remove repeated word'), findsNothing);
    }, variant: macOnly);
  });
}
