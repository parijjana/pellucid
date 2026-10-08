// Description: Bullet style Setting (slice 5b, backlog item 9). Four glyph sets,
// display only (files keep `-`), drawn in the stored length, stored like the
// other settings, applied in the editor and in EPUB export. Numbering stays
// 1. a. i. whatever the set.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/list_marker.dart';
import 'package:pellucid/features/editor/providers/editor_font.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/services/export_service.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';

class _MockDb extends Mock implements SettingsDatabase {}

class _MockStorage extends Mock implements StorageService {}

void main() {
  test('four sets, classic by default, ids round-trip, unknown ids fall back', () {
    expect(BulletStyle.values.map((b) => b.id), ['classic', 'dashes', 'arrows', 'circles']);
    expect(BulletStyle.values.map((b) => b.glyphs.join(' ')), ['• ◦ ▪', '– – –', '▸ ▹ ▸', '● ○ ●']);
    expect(BulletStyle.defaultStyle, BulletStyle.classic);
    expect(BulletStyle.fromId('arrows'), BulletStyle.arrows);
    expect(BulletStyle.fromId('nope'), BulletStyle.classic);
    expect(BulletStyle.fromId(null), BulletStyle.classic);
  });

  test('every glyph is one UTF-16 unit, so a drawn marker keeps the stored length', () {
    for (final b in BulletStyle.values) {
      for (final g in b.glyphs) {
        expect(g.length, 1, reason: '${b.id} $g');
      }
      for (int level = 0; level < 6; level++) {
        final m = parseListMarker('${'    ' * level}- item')!;
        final g = listGlyph(m, b);
        expect(g.shown.length + g.pad, m.marker.length, reason: '${b.id} level $level');
        expect(g.shown, '${b.glyphForLevel(level)} ');
      }
    }
  });

  test('numbering and checkboxes do not depend on the bullet set', () {
    final n = parseListMarker('    1. x')!;
    final c = parseListMarker('- [x] y')!;
    for (final b in BulletStyle.values) {
      expect(listGlyph(n, b).shown, 'a. ');
      expect(listGlyph(c, b).shown, '$checkboxOn ');
    }
  });

  test('visibleText draws the chosen set when asked', () {
    expect(visibleText('- a\n    - b'), '• a\n    ◦ b');
    expect(visibleText('- a\n    - b', bullets: BulletStyle.arrows), '▸ a\n    ▹ b');
  });

  test('SettingsProvider stores the choice like the other settings', () {
    final db = _MockDb();
    when(() => db.getMirroredProjects()).thenAnswer((_) async => <String>{});
    when(() => db.updateSetting(any(), any())).thenAnswer((_) async {});
    final p = SettingsProvider(settingsDatabase: db, storageService: _MockStorage());
    expect(p.bulletStyle, BulletStyle.classic);
    p.setBulletStyle(BulletStyle.circles);
    expect(p.bulletStyle, BulletStyle.circles);
    verify(() => db.updateSetting('bullet_style', 'circles')).called(1);
  });

  testWidgets('the editor draws the chosen set; the stored text keeps "-"', (tester) async {
    final c = MarkdownEditingController(text: '- one\n    - two\n        - three\n    1. num', theme: WriterTheme.presets.first);
    late TextSpan root;
    Future<void> build() async {
      await tester.pumpWidget(Builder(builder: (context) {
        root = c.buildTextSpan(context: context, style: const TextStyle(), withComposing: false);
        return const SizedBox();
      }));
    }

    await build();
    expect(root.toPlainText(), contains('•'));
    c.bulletStyle = BulletStyle.arrows;
    await build();
    final shown = root.toPlainText();
    expect(shown, contains('▸'));
    expect(shown, contains('▹'));
    expect(shown, isNot(contains('•')));
    expect(shown.length, c.text.length);
    expect(c.text, startsWith('- one'));
    expect(shown, contains('a.')); // numbering unchanged
  });

  test('EPUB: classic keeps the stylesheet; other sets add list-style strings', () {
    final classic = ExportService.epubCssFor(EditorFont.serif);
    expect(classic, isNot(contains("list-style-type: '")));
    final arrows = ExportService.epubCssFor(EditorFont.serif, bullets: BulletStyle.arrows);
    expect(arrows, contains("ul { list-style-type: '▸ '; }"));
    expect(arrows, contains("ul ul { list-style-type: '▹ '; }"));
    final bytes = ExportService().buildEpub(markdown: '- a\n- b', title: 'T', author: 'A', bullets: BulletStyle.dashes);
    final css = utf8.decode(ZipDecoder().decodeBytes(bytes).files.firstWhere((f) => f.name.endsWith('styles.css')).content as List<int>);
    expect(css, contains("ul { list-style-type: '– '; }"));
  });
}
