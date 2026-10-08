// Description: Lists in the real editor field (backlog items 2, 8, 17): Tab and
// Shift+Tab, Enter through the text input, Undo straight after an automatic
// marker, and clicking a checklist box.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pellucid/core/platform_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/list_editing.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/editor_paper_area.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:provider/provider.dart';

class _MockEditorProvider extends Mock implements EditorProvider {}

void main() {
  late MarkdownEditingController controller;
  late FocusNode focusNode;
  late List<String> changes;

  setUp(() {
    listAutoContinueEnabled = true;
    lastAutoMarker = null;
  });

  Future<void> pumpEditor(WidgetTester tester, String text, {TextSelection? selection}) async {
    controller = MarkdownEditingController(text: text, theme: WriterTheme.presets.first);
    controller.selection = selection ?? TextSelection.collapsed(offset: text.length);
    focusNode = FocusNode();
    changes = [];
    final provider = _MockEditorProvider();
    when(() => provider.zoomLevel).thenReturn(1.0);
    when(() => provider.pageWidth).thenReturn(800.0);
    when(() => provider.horizontalPosition).thenReturn(0.5);
    when(() => provider.documentLoadFailed).thenReturn(false);
    when(() => provider.isMirrorProject).thenReturn(false);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<EditorProvider>.value(
          value: provider,
          child: EditorPaperArea(
            theme: WriterTheme.presets.first,
            provider: provider,
            controller: controller,
            scrollController: ScrollController(),
            focusNode: focusNode,
            codexEnabled: false,
            codexIndex: CodexIndex(),
            notes: const [],
            onOpenNote: (_) {},
            spellCheckEnabled: false,
            onChanged: changes.add,
          ),
        ),
      ),
    ));
    focusNode.requestFocus();
    await tester.pump();
    controller.selection = selection ?? TextSelection.collapsed(offset: text.length);
  }

  testWidgets('Tab in a list indents the item; Shift+Tab unindents it', (tester) async {
    await pumpEditor(tester, '- a\n- b');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, '- a\n    - b');
    expect(changes.last, '- a\n    - b');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(controller.text, '- a\n- b');
  });

  testWidgets('Tab outside a list keeps inserting four spaces', (tester) async {
    await pumpEditor(tester, 'Hello');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, 'Hello    ');
  });

  testWidgets('Tab on the first list item changes nothing (nothing to nest under)', (tester) async {
    await pumpEditor(tester, '- a');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, '- a');
  });

  testWidgets('Enter through the text input continues the list; Undo removes just the bullet', (tester) async {
    await pumpEditor(tester, '- one');
    await tester.enterText(find.byType(EditableText), '- one\n');
    await tester.pump();
    expect(controller.text, '- one\n- ');
    expect(controller.selection.baseOffset, 8);

    final isMac = usesCommandModifier;
    await tester.sendKeyDownEvent(isMac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(isMac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, '- one\n');
    expect(controller.selection.baseOffset, 6);
    expect(changes.last, '- one\n');
  });

  testWidgets('with auto-continue off, Enter is a plain line break', (tester) async {
    listAutoContinueEnabled = false;
    await pumpEditor(tester, '- one');
    await tester.enterText(find.byType(EditableText), '- one\n');
    await tester.pump();
    expect(controller.text, '- one\n');
  });

  testWidgets('clicking the box ticks it; clicking the text does not', (tester) async {
    await pumpEditor(tester, '- [ ] task\nplain', selection: const TextSelection.collapsed(offset: 15));
    final editable = find.byType(EditableText);
    final topLeft = tester.getTopLeft(editable);
    // The box is the first glyph of the first line.
    await tester.tapAt(topLeft + const Offset(4, 12));
    await tester.pumpAndSettle();
    expect(controller.text, '- [x] task\nplain');
    expect(changes.last, '- [x] task\nplain');

    await tester.tapAt(topLeft + const Offset(4, 12));
    await tester.pumpAndSettle();
    expect(controller.text, '- [ ] task\nplain');

    // A click on the task text only places the caret.
    await tester.tapAt(topLeft + const Offset(90, 12));
    await tester.pumpAndSettle();
    expect(controller.text, '- [ ] task\nplain');
  });
}
