// Description: Tests for Paragraph Focus dimming (MarkdownEditingController)
// and the typewriter/paragraph-focus settings toggles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}
class MockStorageService extends Mock implements StorageService {}

/// Sample document: two-line paragraph, blank line, header block,
/// blank line, closing paragraph.
const String sampleText =
    'First paragraph line one.\nFirst paragraph line two.\n\n# Header block\n\nThird paragraph here.';

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

TextSpan _spanContaining(List<TextSpan> spans, String needle) {
  return spans.firstWhere((s) => s.text!.contains(needle));
}

void main() {
  final theme = WriterTheme.presets[0];
  final Color fg = theme.foregroundColor;
  final Color dim = fg.withValues(alpha: 0.38);

  group('paragraphLineRange', () {
    final lines = sampleText.split('\n');

    test('caret in middle (header) paragraph selects only that block', () {
      final caret = sampleText.indexOf('# Header') + 4;
      expect(MarkdownEditingController.paragraphLineRange(lines, caret),
          equals((startLine: 3, endLine: 3)));
    });

    test('caret in first paragraph spans both contiguous lines', () {
      expect(MarkdownEditingController.paragraphLineRange(lines, 0),
          equals((startLine: 0, endLine: 1)));
      final caretLineTwo = sampleText.indexOf('line two');
      expect(MarkdownEditingController.paragraphLineRange(lines, caretLineTwo),
          equals((startLine: 0, endLine: 1)));
    });

    test('caret in last paragraph selects the final line', () {
      final caret = sampleText.indexOf('Third') + 3;
      expect(MarkdownEditingController.paragraphLineRange(lines, caret),
          equals((startLine: 5, endLine: 5)));
    });

    test('caret on a blank line is its own empty paragraph', () {
      final blankOffset = 'First paragraph line one.\nFirst paragraph line two.\n'.length;
      expect(MarkdownEditingController.paragraphLineRange(lines, blankOffset),
          equals((startLine: 2, endLine: 2)));
    });

    test('single-paragraph document covers all lines', () {
      const doc = 'only one\nparagraph';
      final docLines = doc.split('\n');
      expect(MarkdownEditingController.paragraphLineRange(docLines, 3),
          equals((startLine: 0, endLine: 1)));
      expect(MarkdownEditingController.paragraphLineRange(docLines, doc.length),
          equals((startLine: 0, endLine: 1)));
    });

    test('invalid offsets return null', () {
      expect(MarkdownEditingController.paragraphLineRange(lines, -1), isNull);
      expect(MarkdownEditingController.paragraphLineRange(lines, sampleText.length + 5), isNull);
    });
  });

  group('Paragraph Focus dimming', () {
    late TextStyle baseStyle;

    setUp(() {
      baseStyle = TextStyle(color: fg, fontSize: 16.0, height: 1.8, fontFamily: 'Georgia');
    });

    Future<BuildContext> pumpContext(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      return tester.element(find.byType(SizedBox));
    }

    testWidgets('dims text outside the caret paragraph, keeps caret paragraph at full contrast',
        (WidgetTester tester) async {
      final context = await pumpContext(tester);
      final controller = MarkdownEditingController(text: sampleText, theme: theme);
      controller.selection = TextSelection.collapsed(offset: sampleText.indexOf('Third') + 2);
      controller.paragraphFocusEnabled = true;

      final spans = _flatten(controller.buildTextSpan(
          context: context, style: baseStyle, withComposing: false));

      // Outside paragraph: dimmed (plain text and header content).
      expect(_spanContaining(spans, 'First paragraph line one.').style!.color, equals(dim));
      expect(_spanContaining(spans, 'Header block').style!.color, equals(dim));
      // Caret paragraph: full contrast.
      expect(_spanContaining(spans, 'Third paragraph here.').style!.color, equals(fg));
      // Hidden markdown tag stays hidden regardless of dimming.
      expect(_spanContaining(spans, '# ').style!.color, equals(Colors.transparent));

      controller.dispose();
    });

    testWidgets('caret on a blank line dims every surrounding paragraph',
        (WidgetTester tester) async {
      final context = await pumpContext(tester);
      final controller = MarkdownEditingController(text: sampleText, theme: theme);
      final blankOffset = 'First paragraph line one.\nFirst paragraph line two.\n'.length;
      controller.selection = TextSelection.collapsed(offset: blankOffset);
      controller.paragraphFocusEnabled = true;

      final spans = _flatten(controller.buildTextSpan(
          context: context, style: baseStyle, withComposing: false));

      expect(_spanContaining(spans, 'First paragraph line one.').style!.color, equals(dim));
      expect(_spanContaining(spans, 'Header block').style!.color, equals(dim));
      expect(_spanContaining(spans, 'Third paragraph here.').style!.color, equals(dim));

      controller.dispose();
    });

    testWidgets('feature off produces spans identical to the default build',
        (WidgetTester tester) async {
      final context = await pumpContext(tester);
      final baseline = MarkdownEditingController(text: sampleText, theme: theme);
      final baselineSpan = baseline.buildTextSpan(
          context: context, style: baseStyle, withComposing: false);

      final disabled = MarkdownEditingController(text: sampleText, theme: theme);
      disabled.selection = TextSelection.collapsed(offset: sampleText.indexOf('Third'));
      disabled.paragraphFocusEnabled = false;
      final disabledSpan = disabled.buildTextSpan(
          context: context, style: baseStyle, withComposing: false);

      expect(disabledSpan, equals(baselineSpan));

      // Enabled but with an invalid selection: falls back to no dimming.
      final invalidSelection = MarkdownEditingController(text: sampleText, theme: theme);
      invalidSelection.paragraphFocusEnabled = true;
      final invalidSpan = invalidSelection.buildTextSpan(
          context: context, style: baseStyle, withComposing: false);

      expect(invalidSpan, equals(baselineSpan));

      baseline.dispose();
      disabled.dispose();
      invalidSelection.dispose();
    });

    testWidgets('search-match highlight backgrounds survive dimming',
        (WidgetTester tester) async {
      final context = await pumpContext(tester);
      final controller = MarkdownEditingController(text: sampleText, theme: theme);
      controller.selection = TextSelection.collapsed(offset: sampleText.indexOf('Third') + 2);
      controller.paragraphFocusEnabled = true;
      controller.searchQuery = 'paragraph';

      final spans = _flatten(controller.buildTextSpan(
          context: context, style: baseStyle, withComposing: false));

      // A match inside a dimmed paragraph: dim foreground + visible highlight.
      final dimmedMatch = spans.firstWhere(
          (s) => s.text == 'paragraph' && s.style!.color == dim);
      expect(dimmedMatch.style!.backgroundColor,
          equals(Colors.amber.withValues(alpha: 0.35)));

      // A match inside the focused paragraph keeps full contrast + highlight.
      final focusedMatch = spans.firstWhere(
          (s) => s.text == 'paragraph' && s.style!.color == fg);
      expect(focusedMatch.style!.backgroundColor,
          equals(Colors.amber.withValues(alpha: 0.35)));

      controller.dispose();
    });
  });

  group('SettingsProvider focus mode toggles', () {
    late SettingsProvider settingsProvider;
    late MockSettingsDatabase mockDb;
    late MockStorageService mockStorage;

    setUp(() {
      mockDb = MockSettingsDatabase();
      when(() => mockDb.getMirroredProjects()).thenAnswer((_) async => <String>{});
      mockStorage = MockStorageService();
      settingsProvider = SettingsProvider(
        settingsDatabase: mockDb,
        storageService: mockStorage,
      );
    });

    test('both features default to off', () {
      expect(settingsProvider.typewriterEnabled, false);
      expect(settingsProvider.paragraphFocusEnabled, false);
    });

    test('toggleTypewriter updates state and persists', () {
      when(() => mockDb.updateSetting(any(), any())).thenAnswer((_) async {});

      settingsProvider.toggleTypewriter(true);

      expect(settingsProvider.typewriterEnabled, true);
      verify(() => mockDb.updateSetting('typewriter_enabled', true)).called(1);
    });

    test('toggleParagraphFocus updates state and persists', () {
      when(() => mockDb.updateSetting(any(), any())).thenAnswer((_) async {});

      settingsProvider.toggleParagraphFocus(true);

      expect(settingsProvider.paragraphFocusEnabled, true);
      verify(() => mockDb.updateSetting('paragraph_focus_enabled', true)).called(1);
    });

    test('loadSettings restores persisted values', () async {
      when(() => mockDb.getSettings()).thenAnswer((_) async => {
        'typewriter_enabled': 1,
        'paragraph_focus_enabled': 1,
      });

      await settingsProvider.loadSettings();

      expect(settingsProvider.typewriterEnabled, true);
      expect(settingsProvider.paragraphFocusEnabled, true);
    });
  });
}
