import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/widgets/editor_paper_area.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';

class MockEditorProvider extends Mock implements EditorProvider {}

void main() {
  testWidgets('Pressing Tab inserts 4 spaces in EditorPaperArea', (WidgetTester tester) async {
    final controller = TextEditingController(text: 'Hello');
    final scrollController = ScrollController();
    final focusNode = FocusNode();
    String changedText = '';

    final mockProvider = MockEditorProvider();
    when(() => mockProvider.zoomLevel).thenReturn(1.0);
    when(() => mockProvider.pageWidth).thenReturn(800.0);
    when(() => mockProvider.horizontalPosition).thenReturn(0.5);
    when(() => mockProvider.documentLoadFailed).thenReturn(false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<EditorProvider>.value(
            value: mockProvider,
            child: EditorPaperArea(
              theme: WriterTheme.presets.first,
              provider: mockProvider,
              controller: controller,
              scrollController: scrollController,
              focusNode: focusNode,
              codexEnabled: false,
              codexIndex: CodexIndex(),
              notes: const [],
              onOpenNote: (_) {},
              spellCheckEnabled: true,
              onChanged: (val) {
                changedText = val;
              },
            ),
          ),
        ),
      ),
    );

    // Focus the text field
    focusNode.requestFocus();
    await tester.pump();

    // Place selection at the end of 'Hello'
    controller.selection = const TextSelection.collapsed(offset: 5);

    // Send Tab key event
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    // Check if 4 spaces are inserted
    expect(controller.text, 'Hello    ');
    expect(changedText, 'Hello    ');
    expect(controller.selection.baseOffset, 9);
  });
}
