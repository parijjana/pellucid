import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';

class MockEditorProvider extends Mock implements EditorProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class MockSettingsProvider extends Mock implements SettingsProvider {}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockHistoryProvider extends Mock implements HistoryProvider {}
class MockNotesProvider extends Mock implements NotesProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('window_manager');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  late MockEditorProvider mockEditor;
  late MockThemeProvider mockTheme;
  late MockSettingsProvider mockSettings;
  late MockSyncProvider mockSync;
  late MockHistoryProvider mockHistory;
  late MockNotesProvider mockNotes;
  late SearchProvider searchProvider;
  late ShortcutsProvider shortcutsProvider;

  Future<void> pumpEditor(WidgetTester tester, String content) async {
    when(() => mockEditor.content).thenReturn(content);
    when(() => mockEditor.documentLoadFailed).thenReturn(false);
    when(() => mockEditor.isMirrorProject).thenReturn(false);
    when(() => mockEditor.zoomLevel).thenReturn(1.0);
    when(() => mockEditor.pageWidth).thenReturn(800.0);
    when(() => mockEditor.horizontalPosition).thenReturn(0.5);
    when(() => mockEditor.updateContent(any(),
            syncProvider: any(named: 'syncProvider'),
            projectName: any(named: 'projectName'),
            syncInterval: any(named: 'syncInterval')))
        .thenAnswer((_) async {});

    when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets.first);

    when(() => mockSettings.currentProjectName).thenReturn('Test Project');
    when(() => mockSettings.currentProjectPath).thenReturn('/test/project');
    when(() => mockSettings.masterDirectoryPath).thenReturn('/test/master');
    when(() => mockSettings.clockEnabled).thenReturn(false);
    when(() => mockSettings.currentSessionEnabled).thenReturn(false);
    when(() => mockSettings.targetSessionEnabled).thenReturn(false);
    when(() => mockSettings.focusTimerEnabled).thenReturn(false);
    when(() => mockSettings.isAlarmTriggered).thenReturn(false);
    when(() => mockSettings.batteryGuardEnabled).thenReturn(false);
    when(() => mockSettings.showBatteryPercentage).thenReturn(false);
    when(() => mockSettings.batteryAlertThreshold).thenReturn(20);
    when(() => mockSettings.syncIntervalMinutes).thenReturn(30);
    when(() => mockSettings.typewriterEnabled).thenReturn(false);
    when(() => mockSettings.paragraphFocusEnabled).thenReturn(false);
    when(() => mockSettings.codexLinkingEnabled).thenReturn(false);
    when(() => mockSettings.tocWordCountsEnabled).thenReturn(true);
    when(() => mockSettings.spellCheckEnabled).thenReturn(true);

    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());
    when(() => mockHistory.setEditorFocus(any())).thenReturn(null);
    when(() => mockHistory.saveStatsNow()).thenAnswer((_) async {});

    when(() => mockNotes.cards).thenReturn([]);
    when(() => mockNotes.categories).thenReturn(['general', 'people', 'places', 'events']);

    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
          ChangeNotifierProvider<HistoryProvider>.value(value: mockHistory),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
          ChangeNotifierProvider<SearchProvider>.value(value: searchProvider),
          ChangeNotifierProvider<ShortcutsProvider>.value(value: shortcutsProvider),
          ChangeNotifierProvider<SprintController>(create: (_) => SprintController()),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    mockEditor = MockEditorProvider();
    mockTheme = MockThemeProvider();
    mockSettings = MockSettingsProvider();
    mockSync = MockSyncProvider();
    mockHistory = MockHistoryProvider();
    mockNotes = MockNotesProvider();
    searchProvider = SearchProvider();
    shortcutsProvider = ShortcutsProvider();
  });

  testWidgets('toggling the chevron reveals the replace row', (tester) async {
    await pumpEditor(tester, 'cat and cat and cat');
    searchProvider.toggleSearch(isOpen: true);
    await tester.pump();

    expect(find.byKey(const Key('search_replace_field')), findsNothing);

    await tester.tap(find.byKey(const Key('search_replace_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search_replace_field')), findsOneWidget);
  });

  testWidgets('Replace (one) replaces the current match and advances to the next', (tester) async {
    await pumpEditor(tester, 'cat and cat and cat');
    searchProvider.toggleSearch(isOpen: true);
    await tester.pump();

    await tester.enterText(find.byKey(const Key('search_query_field')), 'cat');
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search_replace_toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search_replace_field')), 'dog');
    await tester.pump();

    await tester.tap(find.byKey(const Key('search_replace_one_button')));
    await tester.pump();

    final manuscriptField = tester.widget<TextField>(find.byType(TextField).first);
    expect(manuscriptField.controller!.text, 'dog and cat and cat');
    // Two "cat" matches remain; the index stayed put, which now points at the
    // occurrence that used to be next -- i.e. Replace advanced forward.
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('Replace All collapses matches to zero and a single Ctrl+Z restores the original text', (tester) async {
    const original = 'cat and cat and cat';
    await pumpEditor(tester, original);

    // A real user has clicked into the manuscript at some point before
    // invoking Replace All -- that's what gives the field a *valid* selection
    // and lets EditableText's built-in undo history capture the pristine text
    // as a baseline entry (an invalid/never-focused selection is rejected by
    // its `shouldChangeUndoStack` check, so a document that was never focused
    // has nothing to undo back to). The baseline push is itself throttled by
    // ~500ms, so pump past that before moving on.
    final manuscriptFinderSetup = find.byType(TextField).first;
    final setupField = tester.widget<TextField>(manuscriptFinderSetup);
    setupField.focusNode!.requestFocus();
    setupField.controller!.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump(const Duration(milliseconds: 600));

    searchProvider.toggleSearch(isOpen: true);
    await tester.pump();

    await tester.enterText(find.byKey(const Key('search_query_field')), 'cat');
    await tester.pump();

    await tester.tap(find.byKey(const Key('search_replace_toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search_replace_field')), 'dog');
    await tester.pump();

    await tester.tap(find.byKey(const Key('search_replace_all_button')));
    await tester.pump();

    final manuscriptFinder = find.byType(TextField).first;
    var manuscriptField = tester.widget<TextField>(manuscriptFinder);
    expect(manuscriptField.controller!.text, 'dog and dog and dog');
    expect(find.text('0 of 0'), findsOneWidget);

    // Focus the manuscript field and undo the bulk replace in a single step.
    final focusNode = manuscriptField.focusNode!;
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    manuscriptField = tester.widget<TextField>(manuscriptFinder);
    expect(manuscriptField.controller!.text, original);
  });
}
