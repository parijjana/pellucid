// Description: The toolbar and macOS Format menu show the formatting at the
// caret (backlog item 25).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/caret_formatting.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/format_menu.dart';
import 'package:pellucid/features/editor/widgets/formatting_toolbar.dart';
import 'package:pellucid/features/editor/widgets/mobile_persistent_toolbar.dart';

FormattingState at(String text, int base, [int? extent]) =>
    formattingAt(text, TextSelection(baseOffset: base, extentOffset: extent ?? base));

void main() {
  group('formattingAt', () {
    //          0123456789012345678
    const t = 'a **bold** *it* <u>u</u>';
    test('caret inside and at the end of a run reports it; at its start does not', () {
      expect(at(t, 5).bold, isTrue);
      expect(at(t, 8).bold, isTrue); // end of "bold": typing continues it
      expect(at(t, 2).bold, isFalse); // before the opening marker
      expect(at(t, 1), FormattingState.none);
    });
    test('italic, underline and nesting', () {
      expect(at(t, 13).italic, isTrue);
      expect(at(t, 20).underline, isTrue);
      final nested = at('**<u>x</u>**', 6);
      expect(nested.bold && nested.underline, isTrue);
      final both = at('***x***', 4);
      expect(both.bold && both.italic, isTrue);
    });
    test('a selection is bold only when every visible letter is', () {
      expect(at(t, 5, 8).bold, isTrue);
      expect(at(t, 3, 10).bold, isTrue, reason: 'selection includes the hidden markers');
      expect(at(t, 0, 8).bold, isFalse);
    });
    test('block style and list come from the line', () {
      expect(at('# T', 3).block, BlockStyle.title);
      expect(at('## H', 4).block, BlockStyle.heading);
      expect(at('### S', 5).block, BlockStyle.subheading);
      expect(at('- b', 3).list, ListStyle.bullet);
      expect(at('x\n# T', 0).block, BlockStyle.body);
    });
    test('a selection spanning many lines stops scanning once nothing can match', () {
      final big = List.filled(20000, 'plain line').join('\n');
      final sw = Stopwatch()..start();
      expect(at(big, 0, big.length), FormattingState.none);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  group('toolbars', () {
    final theme = WriterTheme.presets[0];

    Color? bg(WidgetTester tester, String label) =>
        tester.widget<TextButton>(find.byKey(ValueKey('format-$label'))).style!.backgroundColor?.resolve({});

    testWidgets('desktop toolbar marks the active styles', (tester) async {
      final f = ValueNotifier(const FormattingState(bold: true, block: BlockStyle.heading));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: FormattingToolbar(theme: theme, onApplyFormat: (_) {}, formatting: f))));
      expect(bg(tester, 'BOLD'), formatActiveTint(theme));
      expect(bg(tester, 'HEADING'), formatActiveTint(theme));
      expect(bg(tester, 'ITALIC'), isNull);
      expect(bg(tester, 'BODY'), isNull);

      f.value = const FormattingState(italic: true, list: ListStyle.bullet);
      await tester.pump();
      expect(bg(tester, 'BOLD'), isNull);
      expect(bg(tester, 'ITALIC'), formatActiveTint(theme));
      expect(bg(tester, 'BULLET'), formatActiveTint(theme));
      expect(bg(tester, 'BODY'), isNull);
    });

    testWidgets('mobile toolbar marks the active styles', (tester) async {
      final f = ValueNotifier(const FormattingState(block: BlockStyle.title));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MobilePersistentToolbar(theme: theme, onApplyFormat: (_) {}, onSettingsTap: () {}, formatting: f))));
      expect(bg(tester, 'TITLE'), formatActiveTint(theme));
      expect(bg(tester, 'BODY'), isNull);
    });
  });

  test('macOS Format menu ticks the active styles', () {
    final items = formatMenuItems(const FormattingState(bold: true, underline: true));
    final labels = items.whereType<PlatformMenuItem>().map((i) => i.label).where((l) => l.isNotEmpty).toList();
    expect(labels, [
      '   Title',
      '   Heading',
      '   Subheading',
      '✓ Body',
      '   Bullet',
      '   Quote',
      '✓ Bold',
      '   Italic',
      '✓ Underline',
      '   Strikethrough',
    ]);
  });
}
