// Description: The blank page must be inert when the document could not be read.
//
// The read-failure latch is invisible by design — nothing is saved, nothing is
// synced. That is exactly why it needs saying on screen and needs the TextField
// to refuse keystrokes: a writer typing into a page that silently discards the
// work is a worse outcome than the original bug.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';
import 'package:pellucid/features/editor/widgets/editor_paper_area.dart';

class MockEditorProvider extends Mock implements EditorProvider {}

void main() {
  Future<void> pumpPaperArea(WidgetTester tester, {required bool loadFailed}) async {
    final provider = MockEditorProvider();
    when(() => provider.zoomLevel).thenReturn(1.0);
    when(() => provider.pageWidth).thenReturn(800.0);
    when(() => provider.horizontalPosition).thenReturn(0.5);
    when(() => provider.documentLoadFailed).thenReturn(loadFailed);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<EditorProvider>.value(
            value: provider,
            child: EditorPaperArea(
              theme: WriterTheme.presets.first,
              provider: provider,
              controller: TextEditingController(text: 'The real manuscript'),
              scrollController: ScrollController(),
              focusNode: FocusNode(),
              codexEnabled: false,
              codexIndex: CodexIndex(),
              notes: const [],
              onOpenNote: (_) {},
              spellCheckEnabled: false,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the editor is read-only when the document failed to load',
      (tester) async {
    await pumpPaperArea(tester, loadFailed: true);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);
  });

  testWidgets('the editor stays writable on a normal load', (tester) async {
    await pumpPaperArea(tester, loadFailed: false);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isFalse);
  });

  testWidgets('the failure banner says editing is off and offers a retry',
      (tester) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentLoadFailedBanner(
            theme: WriterTheme.presets.first,
            error: Exception('operation not permitted'),
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.textContaining("couldn't be opened"), findsOneWidget);
    expect(find.textContaining('operation not permitted'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
