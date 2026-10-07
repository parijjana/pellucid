// Description: Behaviour that only exists once the 1.1.0 slices meet in the
// integration branch (slice 4 marker editing/rich copy, slice 6 formats,
// slice 7 context menu, slice 8 grammar hints and smart punctuation).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/rich_clipboard.dart';
import 'package:pellucid/features/editor/marker_aware_editing.dart';
import 'package:pellucid/features/editor/caret_formatting.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/marker_edit_rules.dart';
import 'package:pellucid/features/editor/utils/smart_punctuation.dart';
import 'package:pellucid/features/editor/widgets/format_menu.dart';
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

  group('slice 4 rules cover slice 6 strikethrough and block quotes', () {
    TextEditingValue v(String t, int b, [int? e]) =>
        TextEditingValue(text: t, selection: TextSelection(baseOffset: b, extentOffset: e ?? b));
    TextEditingValue backspace(String t, int p) =>
        applyMarkerEditRules(v(t, p), v(t.substring(0, p - 1) + t.substring(p), p - 1));

    test('quote prefix and ~~ are hidden; quote text keeps inline runs', () {
      final line = scanLine('> a **b** ~~c~~', 0, 15);
      expect(line.prefix, '> ');
      expect(line.isHidden(0), isTrue);
      expect(line.isHidden(1), isTrue);
      expect(line.runs.map((r) => r.tag), ['**', '~~']);
      expect(visibleText('> a **b** ~~c~~'), 'a b c');
    });

    test('caret steps over ~~ in one press', () {
      //         0123456789
      const t = 'x ~~gone~~ y';
      expect(stepRight(t, 2), 5); // before ~~ -> after the g
      expect(stepLeft(t, 10), 7);  // after closing ~~ -> before the e
    });

    test('formatting at the caret reports quote and strikethrough', () {
      final q = formattingAt('> a **b**', const TextSelection.collapsed(offset: 7));
      expect(q.block, BlockStyle.quote);
      expect(q.bold, isTrue);
      final s = formattingAt('x ~~gone~~', const TextSelection.collapsed(offset: 6));
      expect(s.strikethrough, isTrue);
      final sel = formattingAt('x ~~gone~~', const TextSelection(baseOffset: 4, extentOffset: 8));
      expect(sel.strikethrough, isTrue);
    });

    test('Format menu ticks Subheading, Quote and Strikethrough', () {
      String label(FormattingState f, String name) => formatMenuItems(f)
          .whereType<PlatformMenuItem>()
          .map((i) => i.label)
          .firstWhere((l) => l.endsWith(name));
      expect(label(const FormattingState(block: BlockStyle.subheading), 'Subheading'), '✓ Subheading');
      expect(label(const FormattingState(block: BlockStyle.quote), 'Quote'), '✓ Quote');
      expect(label(const FormattingState(strikethrough: true), 'Strikethrough'), '✓ Strikethrough');
    });

    test('Backspace at the start of a quote line removes the quote first', () {
      final once = backspace('ab\n> Quote', 5);
      expect(once.text, 'ab\nQuote');
    });

    test('deleting the last struck letter leaves no stray ~~~~', () {
      final out = backspace('a ~~x~~ b', 5);
      expect(out.text, 'a  b');
    });

    test('strikethrough toggled on at a bare caret opens a hidden empty run', () {
      final toggle = toggleInlineAtCaret('a b', 2, '~~');
      expect(toggle, isNotNull);
      expect(toggle!.text, 'a ~~~~b');
      expect(visibleText(toggle.text), 'a b');
    });

    test('rich copy keeps strikethrough and quotes', () {
      expect(markdownFor('a ~~gone~~ b', 0, 12), 'a ~~gone~~ b');
      expect(markdownFor('a ~~gone~~ b', 0, 7), 'a ~~gon~~');
      expect(plainTextFor('> a ~~gone~~', 0, 12), 'a gone');
      expect(htmlFor('> a ~~gone~~', 0, 12), contains('<blockquote>a <s>gone</s></blockquote>'));
    });
  });

  group('slice 8 smart punctuation runs after slice 4 marker rules', () {
    // The editor's formatter order: [MarkerEditFormatter, SmartPunctuationFormatter].
    TextEditingValue typeAt(String t, int at, String ins) {
      var old = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: at));
      var proposed = TextEditingValue(
          text: t.replaceRange(at, at, ins), selection: TextSelection.collapsed(offset: at + ins.length));
      final afterMarkers = const MarkerEditFormatter().formatEditUpdate(old, proposed);
      return SmartPunctuationFormatter().formatEditUpdate(old, afterMarkers);
    }

    test('an apostrophe typed at the end of a bold run is curly and stays in the run', () {
      final out = typeAt('**dog**', 5, "'");
      expect(out.text, '**dog’**');
      expect(out.selection.baseOffset, 6);
    });

    test('-- inside struck text becomes an em dash and the markers stay balanced', () {
      final out = typeAt('~~a-b~~', 4, '-');
      expect(out.text, '~~a—b~~');
      expect(visibleText(out.text), 'a—b');
    });

    test('an opening quote at the start of a quote line is curly', () {
      final out = typeAt('> ', 2, '"');
      expect(out.text, '> “');
    });
  });
}
