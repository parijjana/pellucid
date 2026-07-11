// Description: Tests for Codex Linking — mention matching (CodexIndex) and its
// integration into the MarkdownEditingController span tree (underline coexisting
// with search highlighting and paragraph-focus dimming), plus the settings toggle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}
class MockStorageService extends Mock implements StorageService {}

List<TextSpan> _flatten(InlineSpan root) {
  final List<TextSpan> out = [];
  void collect(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null && span.text!.isNotEmpty) out.add(span);
      span.children?.forEach(collect);
    }
  }
  collect(root);
  return out;
}

void main() {
  group('CodexIndex matching', () {
    late CodexIndex index;

    setUp(() => index = CodexIndex());

    test('recognises whole-word titles and records note ids', () {
      index.setTitles(const [
        CodexTitle(id: 'a', title: 'Alice'),
        CodexTitle(id: 'b', title: 'Bob'),
      ]);
      final ranges = index.rangesFor('Alice met Bob today.');
      expect(ranges.length, 2);
      expect(ranges[0].start, 0);
      expect(ranges[0].end, 5);
      expect(ranges[0].noteId, 'a');
      expect(ranges[1].noteId, 'b');
    });

    test('does not match substrings inside larger words', () {
      index.setTitles(const [CodexTitle(id: 'a', title: 'Alice')]);
      expect(index.rangesFor('malice and Alicexyz').isEmpty, isTrue);
    });

    test('is case-sensitive (proper nouns only)', () {
      index.setTitles(const [CodexTitle(id: 'a', title: 'Alice')]);
      final ranges = index.rangesFor('alice ALICE Alice');
      expect(ranges.length, 1);
      expect(ranges.single.start, 'alice ALICE '.length);
    });

    test('skips trivial titles shorter than 3 chars (after trim)', () {
      index.setTitles(const [
        CodexTitle(id: 'a', title: 'Al'),
        CodexTitle(id: 'b', title: ' K '),
        CodexTitle(id: 'c', title: 'Zed'),
      ]);
      final ranges = index.rangesFor('Al K Zed');
      expect(ranges.length, 1);
      expect(ranges.single.noteId, 'c');
    });

    test('matches multi-word titles and prefers the longest', () {
      index.setTitles(const [
        CodexTitle(id: 'n', title: 'New'),
        CodexTitle(id: 'ny', title: 'New York'),
      ]);
      final ranges = index.rangesFor('Meet me in New York.');
      expect(ranges.length, 1);
      expect(ranges.single.noteId, 'ny');
      expect(ranges.single.end - ranges.single.start, 'New York'.length);
    });

    test('caches ranges by text identity (O(1) repaint path)', () {
      index.setTitles(const [CodexTitle(id: 'a', title: 'Alice')]);
      const text = 'Alice again';
      final first = index.rangesFor(text);
      final second = index.rangesFor(text);
      expect(identical(first, second), isTrue);
    });

    test('noteIdAt resolves offsets within a mention', () {
      index.setTitles(const [CodexTitle(id: 'a', title: 'Alice')]);
      index.rangesFor('Alice waved.');
      expect(index.noteIdAt(0), 'a');
      expect(index.noteIdAt(4), 'a');
      expect(index.noteIdAt(5), isNull); // end is exclusive
      expect(index.noteIdAt(8), isNull);
    });

    test('empty title set produces no ranges', () {
      index.setTitles(const []);
      expect(index.rangesFor('Alice').isEmpty, isTrue);
    });
  });

  group('MarkdownEditingController Codex span integration', () {
    final theme = WriterTheme.presets[0];
    final Color fg = theme.foregroundColor;
    final Color underlineColor = fg.withValues(alpha: 0.18);
    late TextStyle baseStyle;

    setUp(() {
      baseStyle = TextStyle(color: fg, fontSize: 16.0, height: 1.8, fontFamily: 'Georgia');
    });

    Future<BuildContext> pumpContext(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      return tester.element(find.byType(SizedBox));
    }

    testWidgets('mentions get a faint underline when enabled', (tester) async {
      final context = await pumpContext(tester);
      final controller = MarkdownEditingController(text: 'Alice is here.', theme: theme);
      controller.codexTitles = const [CodexTitle(id: 'a', title: 'Alice')];
      controller.codexLinkingEnabled = true;

      final spans = _flatten(controller.buildTextSpan(
          context: context, style: baseStyle, withComposing: false));

      final mention = spans.firstWhere((s) => s.text == 'Alice');
      expect(mention.style!.decoration, TextDecoration.underline);
      expect(mention.style!.decorationColor, underlineColor);
      // Surrounding text stays undecorated.
      final rest = spans.firstWhere((s) => s.text!.contains('is here'));
      expect(rest.style!.decoration, anyOf(isNull, TextDecoration.none));

      controller.dispose();
    });

    testWidgets('disabled produces no underline', (tester) async {
      final context = await pumpContext(tester);
      final controller = MarkdownEditingController(text: 'Alice is here.', theme: theme);
      controller.codexTitles = const [CodexTitle(id: 'a', title: 'Alice')];
      controller.codexLinkingEnabled = false;

      final spans = _flatten(controller.buildTextSpan(
          context: context, style: baseStyle, withComposing: false));

      // No span is split out for the mention; nothing carries the underline.
      expect(spans.any((s) => s.style?.decoration == TextDecoration.underline), isFalse);

      controller.dispose();
    });

    testWidgets('underline coexists with search highlight and paragraph dimming',
        (tester) async {
      final context = await pumpContext(tester);
      const doc = 'Alice is here.\n\nSecond paragraph.';
      final controller = MarkdownEditingController(text: doc, theme: theme);
      controller.codexTitles = const [CodexTitle(id: 'a', title: 'Alice')];
      controller.codexLinkingEnabled = true;
      controller.searchQuery = 'Alice';
      // Caret in the second paragraph → the "Alice" line is dimmed.
      controller.selection = TextSelection.collapsed(offset: doc.indexOf('Second') + 2);
      controller.paragraphFocusEnabled = true;

      final spans = _flatten(controller.buildTextSpan(
          context: context, style: baseStyle, withComposing: false));

      final mention = spans.firstWhere((s) => s.text == 'Alice');
      // All three effects land on one span:
      expect(mention.style!.decoration, TextDecoration.underline);       // Codex
      expect(mention.style!.decorationColor, underlineColor);            // Codex
      expect(mention.style!.backgroundColor,
          Colors.amber.withValues(alpha: 0.35));                        // search
      expect(mention.style!.color, fg.withValues(alpha: 0.38));         // dim

      controller.dispose();
    });
  });

  group('SettingsProvider codex toggle', () {
    late SettingsProvider settingsProvider;
    late MockSettingsDatabase mockDb;
    late MockStorageService mockStorage;

    setUp(() {
      mockDb = MockSettingsDatabase();
      mockStorage = MockStorageService();
      settingsProvider = SettingsProvider(
        settingsDatabase: mockDb,
        storageService: mockStorage,
      );
    });

    test('defaults to off', () {
      expect(settingsProvider.codexLinkingEnabled, false);
    });

    test('toggleCodexLinking updates state and persists', () {
      when(() => mockDb.updateSetting(any(), any())).thenAnswer((_) async {});
      settingsProvider.toggleCodexLinking(true);
      expect(settingsProvider.codexLinkingEnabled, true);
      verify(() => mockDb.updateSetting('codex_linking_enabled', true)).called(1);
    });

    test('loadSettings restores persisted value', () async {
      when(() => mockDb.getSettings()).thenAnswer((_) async => {
            'codex_linking_enabled': 1,
          });
      await settingsProvider.loadSettings();
      expect(settingsProvider.codexLinkingEnabled, true);
    });
  });
}
