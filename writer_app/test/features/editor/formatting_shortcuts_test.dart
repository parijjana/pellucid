import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';

class MockEditorProvider extends Mock implements EditorProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class MockSettingsProvider extends Mock implements SettingsProvider {
  @override
  bool get spellCheckEnabled => true;
}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockHistoryProvider extends Mock implements HistoryProvider {}
class MockNotesProvider extends Mock implements NotesProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('window_manager');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
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
  late ShortcutsProvider realShortcuts;

  setUp(() {
    mockEditor = MockEditorProvider();
    mockTheme = MockThemeProvider();
    mockSettings = MockSettingsProvider();
    mockSync = MockSyncProvider();
    mockHistory = MockHistoryProvider();
    mockNotes = MockNotesProvider();
    realShortcuts = ShortcutsProvider();

    // Stub EditorProvider
    when(() => mockEditor.content).thenReturn('Hello world');
    when(() => mockEditor.zoomLevel).thenReturn(1.0);
    when(() => mockEditor.pageWidth).thenReturn(800.0);
    when(() => mockEditor.horizontalPosition).thenReturn(0.5);
    when(() => mockEditor.updateContent(any(),
            syncProvider: any(named: 'syncProvider'),
            projectName: any(named: 'projectName'),
            syncInterval: any(named: 'syncInterval')))
        .thenAnswer((_) async {});

    // Stub ThemeProvider
    when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets.first);

    // Stub SettingsProvider
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

    // Stub HistoryProvider
    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());
    when(() => mockHistory.setEditorFocus(any())).thenReturn(null);
    when(() => mockHistory.saveStatsNow()).thenAnswer((_) async {});

    // Stub NotesProvider
    when(() => mockNotes.cards).thenReturn([]);
    when(() => mockNotes.categories).thenReturn(['general', 'people', 'places', 'events']);

    // Stub SyncProvider
    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);
  });

  testWidgets('Ctrl+B and Ctrl+I formatting keyboard shortcuts work in EditorScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
          ChangeNotifierProvider<HistoryProvider>.value(value: mockHistory),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
          ChangeNotifierProvider<SearchProvider>(create: (_) => SearchProvider()),
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
          ChangeNotifierProvider<SprintController>(create: (_) => SprintController()),
        ],
        child: const MaterialApp(
          home: EditorScreen(),
        ),
      ),
    );

    // Find the text field inside EditorScreen and focus it
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    
    final FocusNode focusNode = tester.widget<TextField>(textFieldFinder).focusNode!;
    focusNode.requestFocus();
    await tester.pump();

    final controller = tester.widget<TextField>(textFieldFinder).controller!;
    
    // Select the word 'world' in 'Hello world' (index 6 to 11)
    controller.selection = const TextSelection(baseOffset: 6, extentOffset: 11);

    final modifierKey = Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;

    // Simulate Ctrl+B (Bold)
    await tester.sendKeyDownEvent(modifierKey);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(modifierKey);
    await tester.pump();

    // Verify 'world' wrapped in '**'
    expect(controller.text, 'Hello **world**');

    // Simulate Ctrl+I (Italic)
    controller.selection = const TextSelection(baseOffset: 8, extentOffset: 13); // select 'world'
    await tester.sendKeyDownEvent(modifierKey);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(modifierKey);
    await tester.pump();

    // Verify wrapped in '*'
    expect(controller.text, 'Hello ***world***');

    // Simulate Ctrl+U (Underline)
    controller.selection = const TextSelection(baseOffset: 9, extentOffset: 14); // select 'world'
    await tester.sendKeyDownEvent(modifierKey);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(modifierKey);
    await tester.pump();

    // Verify wrapped in '<u>...</u>'
    expect(controller.text, 'Hello ***<u>world</u>***');
  });

  testWidgets('Set Header shortcut is remapped from Cmd+Opt+H to Cmd+Opt+E', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
          ChangeNotifierProvider<HistoryProvider>.value(value: mockHistory),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
          ChangeNotifierProvider<SearchProvider>(create: (_) => SearchProvider()),
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
          ChangeNotifierProvider<SprintController>(create: (_) => SprintController()),
        ],
        child: const MaterialApp(
          home: EditorScreen(),
        ),
      ),
    );

    // Find the text field inside EditorScreen and focus it
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);

    final FocusNode focusNode = tester.widget<TextField>(textFieldFinder).focusNode!;
    focusNode.requestFocus();
    await tester.pump();

    final controller = tester.widget<TextField>(textFieldFinder).controller!;

    // Collapsed cursor at the start of the line, matching how the line-based
    // header/title/bullet formatting activators expect selection state.
    controller.selection = const TextSelection.collapsed(offset: 0);

    // Formatting shortcuts in Pellucid are unified: Alt/Opt + Key on
    // Windows/Linux, and Cmd + Opt + Key on macOS (see pressShortcut in
    // shortcuts_test.dart for the same pattern).
    final bool isMac = Platform.isMacOS;
    Future<void> pressAltKey(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      if (isMac) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      if (isMac) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }

    // Cmd+Opt+H (the old header binding) must no longer set a header: 'H' has
    // no shortcut bound to it anywhere in the editor anymore, so the content
    // is left untouched.
    await pressAltKey(LogicalKeyboardKey.keyH);
    expect(controller.text, 'Hello world');

    // Cmd+Opt+E (the new header binding) sets the header.
    await pressAltKey(LogicalKeyboardKey.keyE);
    expect(controller.text, '## Hello world');
  });
}
