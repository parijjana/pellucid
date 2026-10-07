import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/editor_paper_area.dart';

class MockEditorProvider extends Mock implements EditorProvider {}

void main() {
  Future<TextEditingController> pump(WidgetTester tester) async {
    final controller = TextEditingController(text: 'Hello');
    final focusNode = FocusNode();
    final p = MockEditorProvider();
    when(() => p.zoomLevel).thenReturn(1.0);
    when(() => p.pageWidth).thenReturn(800.0);
    when(() => p.horizontalPosition).thenReturn(0.5);
    when(() => p.documentLoadFailed).thenReturn(false);
    when(() => p.isMirrorProject).thenReturn(false);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<EditorProvider>.value(
          value: p,
          child: EditorPaperArea(
            theme: WriterTheme.presets.first,
            provider: p,
            controller: controller,
            scrollController: ScrollController(),
            focusNode: focusNode,
            codexEnabled: false,
            codexIndex: CodexIndex(),
            notes: const [],
            onOpenNote: (_) {},
            spellCheckEnabled: false,
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    focusNode.requestFocus();
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField), 'Hello world');
    await tester.pump(const Duration(milliseconds: 600));
    return controller;
  }

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey mod, LogicalKeyboardKey key,
      {bool shift = false}) async {
    await tester.sendKeyDownEvent(mod);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
  }

  for (final c in [
    (TargetPlatform.windows, 'Ctrl+Y', LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyY, false),
    (TargetPlatform.windows, 'Ctrl+Shift+Z', LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ, true),
    (TargetPlatform.linux, 'Ctrl+Y', LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyY, false),
    (TargetPlatform.macOS, 'Cmd+Shift+Z', LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyZ, true),
  ]) {
    testWidgets('${c.$1.name}: ${c.$2} redoes after undo', (tester) async {
      debugDefaultTargetPlatformOverride = c.$1;
      final controller = await pump(tester);
      final undoMod = c.$1 == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await chord(tester, undoMod, LogicalKeyboardKey.keyZ);
      expect(controller.text, 'Hello');
      await chord(tester, c.$3, c.$4, shift: c.$5);
      expect(controller.text, 'Hello world');
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
