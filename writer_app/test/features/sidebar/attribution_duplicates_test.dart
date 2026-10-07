// Description: Duplicate check in the attribution list (backlog item 19): the
// normalisation, the highlight on both sides of a pair, and the softAccent
// theme colour staying readable on every preset.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/sidebar/providers/attribution_duplicates.dart';
import 'package:pellucid/features/sidebar/providers/note_card.dart';
import 'package:pellucid/features/sidebar/widgets/note_editor_attribution_list.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  group('normalisation', () {
    test('trim, collapse whitespace, ignore case', () {
      expect(normalizeAttribution('  Photo   by  ANNA \n'), 'photo by anna');
    });

    test('leading bullets and numbers are ignored', () {
      for (final s in ['* Photo by Anna', '- Photo by Anna', '• Photo by Anna', '3. Photo by Anna', '12) Photo by Anna', '  +  Photo by Anna']) {
        expect(normalizeAttribution(s), 'photo by anna', reason: s);
      }
    });

    test('a number inside the text is kept', () {
      expect(normalizeAttribution('1984 by Orwell'), '1984 by orwell');
    });
  });

  group('duplicateAttributionIndexes', () {
    test('flags both sides of a pair, and every copy of a triple', () {
      expect(duplicateAttributionIndexes(['a', 'b', 'A ', 'c']), {0, 2});
      expect(duplicateAttributionIndexes(['x', 'X', '* x', 'y']), {0, 1, 2});
    });

    test('unique lines and blank lines are not flagged', () {
      expect(duplicateAttributionIndexes(['a', 'b', '', '  ', '-']), isEmpty);
    });

    test('rechecked from scratch: fixing a line clears its partner', () {
      expect(duplicateAttributionIndexes(['a', 'a']), {0, 1});
      expect(duplicateAttributionIndexes(['a', 'a b']), isEmpty);
    });
  });

  testWidgets('duplicate rows are tinted with softAccent, others are not', (tester) async {
    final theme = WriterTheme.presets.first;
    final items = [
      AttributionItem(text: 'Photo by Anna'),
      AttributionItem(text: 'Something else'),
      AttributionItem(text: '* photo  by anna'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditorAttributionList(
          titleController: TextEditingController(),
          items: items,
          attributionType: 'bullet',
          availableNotes: const [],
          theme: theme,
          onTypeChanged: (_) {},
          onItemTextChanged: (_, _) {},
          onItemAdded: (_, _) {},
          onItemDeleted: (_) {},
          onLinkNote: (_, _) {},
          onUnlinkNote: (_, _) {},
          onNavigateToNote: (_) {},
        ),
      ),
    ));
    final tinted = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).color == theme.softAccent);
    expect(tinted.length, 2);
  });

  group('softAccent', () {
    test('text stays readable on the highlight, on every theme', () {
      for (final t in WriterTheme.presets) {
        final text = Color.alphaBlend(t.foregroundColor.withValues(alpha: 0.9), t.softAccent);
        // Solarized is low-contrast by design: hold it to its own page contrast.
        final own = _contrast(t.foregroundColor, t.backgroundColor);
        final need = own < 5.3 ? own * 0.7 : 4.5;
        expect(_contrast(text, t.softAccent), greaterThan(need), reason: t.name);
      }
    });

    test('the highlight is visible against the page but not loud, on every theme', () {
      for (final t in WriterTheme.presets) {
        final c = _contrast(t.softAccent, t.backgroundColor);
        expect(c, greaterThan(1.1), reason: '${t.name} too faint ($c)');
        expect(c, lessThan(2.0), reason: '${t.name} too loud ($c)');
        expect(t.softAccent.a, 1.0, reason: t.name);
      }
    });
  });
}
