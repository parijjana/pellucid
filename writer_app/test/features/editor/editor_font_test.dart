// Item 14: document font as an app-level setting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_font.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/editor/widgets/typewriter_scroll.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';

class _MockDb extends Mock implements SettingsDatabase {}
class _MockStorage extends Mock implements StorageService {}

void main() {
  test('three families: serif, sans, monospace, default serif (Georgia)', () {
    expect(EditorFont.values.map((f) => f.id), ['serif', 'sans', 'monospace']);
    expect(EditorFont.defaultFont, EditorFont.serif);
    expect(EditorFont.serif.family, 'Georgia');
    expect(EditorFont.fromId('nope'), EditorFont.serif);
    expect(EditorFont.fromId('monospace'), EditorFont.monospace);
  });

  test('apply sets the family and fallbacks without losing the base style', () {
    final s = EditorFont.monospace.apply(const TextStyle(fontSize: 20, height: 1.8));
    expect(s.fontFamily, 'Menlo');
    expect(s.fontFamilyFallback, contains('Consolas'));
    expect(s.fontSize, 20);
    expect(s.height, 1.8);
  });

  test('SettingsProvider stores the chosen font', () {
    final db = _MockDb();
    when(() => db.getMirroredProjects()).thenAnswer((_) async => <String>{});
    when(() => db.updateSetting(any(), any())).thenAnswer((_) async {});
    final p = SettingsProvider(settingsDatabase: db, storageService: _MockStorage());
    expect(p.editorFont, EditorFont.serif);
    p.setEditorFont(EditorFont.sans);
    expect(p.editorFont, EditorFont.sans);
    verify(() => db.updateSetting('editor_font', 'sans')).called(1);
  });

  testWidgets('paragraph focus and block spans inherit the chosen family', (tester) async {
    final c = MarkdownEditingController(text: '# Title\n\nbody **bold**', theme: WriterTheme.presets.first)
      ..paragraphFocusEnabled = true
      ..selection = const TextSelection.collapsed(offset: 12);
    final style = EditorFont.sans.apply(const TextStyle(fontSize: 16));
    late TextSpan span;
    await tester.pumpWidget(Builder(builder: (ctx) {
      span = c.buildTextSpan(context: ctx, style: style, withComposing: false);
      return const SizedBox();
    }));
    expect(span.style!.fontFamily, 'Helvetica Neue');
    // Headings inherit; body lines carry the same base style. None switch family.
    final overrides = <String?>[];
    span.visitChildren((s) {
      if (s is TextSpan && s.style?.fontFamily != null) overrides.add(s.style!.fontFamily);
      return true;
    });
    expect(overrides.toSet().difference({'Helvetica Neue'}), isEmpty);
  });

  test('typewriter measurement is parameterised by the font', () {
    // Same text, both fonts resolve without throwing and return a finite offset.
    for (final f in EditorFont.values) {
      final y = typewriterTargetOffset(
        text: List.filled(40, 'some words here').join('\n'),
        caretOffset: 300,
        zoomLevel: 1.0,
        pageWidth: 800,
        viewportHeight: 600,
        font: f,
      );
      expect(y.isFinite, isTrue);
    }
  });
}
