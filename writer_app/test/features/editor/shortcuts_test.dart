import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/features/sidebar/providers/note_card.dart';
import 'package:pellucid/features/sidebar/widgets/note_editor_dialog.dart';
import 'package:pellucid/features/editor/widgets/alarm_setter_dialog.dart';
import 'package:pellucid/features/settings/screens/settings_screen.dart';
import 'package:pellucid/main.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';

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

    when(() => mockEditor.content).thenReturn('# Hello World');
    when(() => mockEditor.zoomLevel).thenReturn(1.0);
    when(() => mockEditor.pageWidth).thenReturn(800.0);
    when(() => mockEditor.horizontalPosition).thenReturn(0.5);

    when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets[0]);

    when(() => mockSettings.currentProjectName).thenReturn('Test Project');
    when(() => mockSettings.currentProjectPath).thenReturn('/test_project');
    when(() => mockSettings.masterDirectoryPath).thenReturn('/test_master');
    when(() => mockSettings.availableProjects).thenReturn([]);
    when(() => mockSettings.clockEnabled).thenReturn(false);
    when(() => mockSettings.currentSessionEnabled).thenReturn(false);
    when(() => mockSettings.targetSessionEnabled).thenReturn(false);
    when(() => mockSettings.focusTimerEnabled).thenReturn(false);
    when(() => mockSettings.isAlarmTriggered).thenReturn(false);
    when(() => mockSettings.batteryGuardEnabled).thenReturn(false);
    when(() => mockSettings.showBatteryPercentage).thenReturn(false);
    when(() => mockSettings.batteryAlertThreshold).thenReturn(20);
    when(() => mockSettings.lastNotesFullscreenState).thenReturn(false);
    when(() => mockSettings.setLastNotesFullscreenState(any())).thenAnswer((_) async {});
    when(() => mockSettings.refreshProjects()).thenAnswer((_) async {});
    when(() => mockSettings.syncIntervalMinutes).thenReturn(30);
    when(() => mockSettings.typewriterEnabled).thenReturn(false);
    when(() => mockSettings.paragraphFocusEnabled).thenReturn(false);
    when(() => mockSettings.codexLinkingEnabled).thenReturn(false);
    when(() => mockSettings.tocWordCountsEnabled).thenReturn(true);
    when(() => mockSettings.dailyWordGoal).thenReturn(0);
    when(() => mockSettings.hasDailyWordGoal).thenReturn(false);

    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);

    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());
    when(() => mockHistory.saveStatsNow()).thenAnswer((_) async {});
    when(() => mockHistory.loadProjectStats(any())).thenAnswer((_) async {});

    when(() => mockNotes.cards).thenReturn([]);
    when(() => mockNotes.categories).thenReturn(['general', 'people', 'places', 'events']);
  });

  Future<void> pressShortcut(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
    bool isSettings = false, // Kept signature compatibility
  }) async {
    final bool isMac = Platform.isMacOS;
    final List<LogicalKeyboardKey> modifiers = [];

    // All standard and settings shortcuts in Pellucid are unified:
    // Alt/Opt + Key on Windows/Linux, and Cmd + Opt + Key on macOS
    modifiers.add(LogicalKeyboardKey.altLeft);
    if (isMac) {
      modifiers.add(LogicalKeyboardKey.metaLeft);
    }

    if (shift) {
      modifiers.add(LogicalKeyboardKey.shiftLeft);
    }

    for (final mod in modifiers) {
      await tester.sendKeyDownEvent(mod);
    }
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    for (final mod in modifiers.reversed) {
      await tester.sendKeyUpEvent(mod);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Keyboard shortcuts trigger actions correctly when Alt + key is pressed', (WidgetTester tester) async {
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
        child: const WriterApp(),
      ),
    );

    // Initial check
    expect(realShortcuts.isLeftSidebarOpen, isFalse);
    expect(realShortcuts.isRightSidebarOpen, isFalse);
    expect(realShortcuts.isToolbarOpen, isFalse);
    expect(realShortcuts.isFullscreen, isFalse);

    // Focus the TextField directly via its focusNode to avoid off-screen tap issues
    final TextField textField = tester.widget<TextField>(find.byType(TextField));
    textField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    // 1. Toggle Left Sidebar
    await pressShortcut(tester, LogicalKeyboardKey.digit1);
    expect(realShortcuts.isLeftSidebarOpen, isTrue);

    // 2. Toggle Right Sidebar
    await pressShortcut(tester, LogicalKeyboardKey.digit2);
    expect(realShortcuts.isRightSidebarOpen, isTrue);

    // 3. Toggle Floating Toolbar
    await pressShortcut(tester, LogicalKeyboardKey.digit3);
    expect(realShortcuts.isToolbarOpen, isTrue);

    // 4. Toggle Fullscreen
    await pressShortcut(tester, LogicalKeyboardKey.enter);
    expect(realShortcuts.isFullscreen, isTrue);

    // 5. Peek Clock
    expect(realShortcuts.isClockPeeked, isFalse);
    await pressShortcut(tester, LogicalKeyboardKey.keyC);
    expect(realShortcuts.isClockPeeked, isTrue);

    // 6. Peek Session
    expect(realShortcuts.isSessionPeeked, isFalse);
    await pressShortcut(tester, LogicalKeyboardKey.keyS);
    expect(realShortcuts.isSessionPeeked, isTrue);

    // Let the 2-second peek timers complete so we do not have pending timers on teardown
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Alt+5 and Alt+6 toggle typewriter scrolling and paragraph focus', (WidgetTester tester) async {
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
        child: const WriterApp(),
      ),
    );

    // Focus the TextField directly via its focusNode to avoid off-screen tap issues
    final TextField textField = tester.widget<TextField>(find.byType(TextField));
    textField.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    final bool isMac = Platform.isMacOS;

    Future<void> triggerShortcut(LogicalKeyboardKey digitKey) async {
      if (isMac) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyDownEvent(digitKey);
        await tester.sendKeyUpEvent(digitKey);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(digitKey);
        await tester.sendKeyUpEvent(digitKey);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      }
      await tester.pumpAndSettle();
    }

    // 1. Toggle Typewriter Scrolling (Alt + 5): off -> on
    await triggerShortcut(LogicalKeyboardKey.digit5);
    verify(() => mockSettings.toggleTypewriter(true)).called(1);

    // 2. Toggle Paragraph Focus (Alt + 6): off -> on
    await triggerShortcut(LogicalKeyboardKey.digit6);
    verify(() => mockSettings.toggleParagraphFocus(true)).called(1);

    // 3. When already enabled, the shortcut toggles back off
    when(() => mockSettings.typewriterEnabled).thenReturn(true);
    when(() => mockSettings.paragraphFocusEnabled).thenReturn(true);

    await triggerShortcut(LogicalKeyboardKey.digit5);
    verify(() => mockSettings.toggleTypewriter(false)).called(1);

    await triggerShortcut(LogicalKeyboardKey.digit6);
    verify(() => mockSettings.toggleParagraphFocus(false)).called(1);
  });

  testWidgets('Fullscreen toggle triggers correctly when F11 is pressed', (WidgetTester tester) async {
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
        child: const WriterApp(),
      ),
    );

    // Focus the TextField directly
    final TextField textField = tester.widget<TextField>(find.byType(TextField));
    textField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(realShortcuts.isFullscreen, isFalse);

    // Press F11
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(realShortcuts.isFullscreen, isTrue);
  });

  testWidgets('Keyboard shortcuts Alt+A, Alt+Shift+A, and double Alt tap work correctly', (WidgetTester tester) async {
    // Stub mockNotes methods for attribution
    final mockNoteCard = NoteCard(
      id: 'attr-id',
      title: 'Attributions',
      content: 'Attribution Content',
      category: 'general',
      isAttribution: true,
    );
    when(() => mockNotes.cards).thenReturn([mockNoteCard]);
    when(() => mockNotes.addAttributionCard(syncProvider: any(named: 'syncProvider'))).thenAnswer((_) async {});
    registerFallbackValue(DateTime.now());

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
        child: const WriterApp(),
      ),
    );

    // Focus the TextField directly
    final TextField textField = tester.widget<TextField>(find.byType(TextField));
    textField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    // Test SetAlarmIntent
    await pressShortcut(tester, LogicalKeyboardKey.keyA, shift: true);

    // Verify that AlarmSetterDialog is opened
    expect(find.byType(AlarmSetterDialog), findsOneWidget);

    // Close the dialog using Escape key
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlarmSetterDialog), findsNothing);

    // Test OpenAttributionIntent
    await pressShortcut(tester, LogicalKeyboardKey.keyA);

    // Verify that NoteEditorDialog is opened
    expect(find.byType(NoteEditorDialog), findsOneWidget);

    // Close the note dialog
    await pressShortcut(tester, LogicalKeyboardKey.keyA);
    expect(find.byType(NoteEditorDialog), findsNothing);

    // Test Double-tap Alt
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // Verify cheatsheet overlay text appears
    expect(find.text('KEYBOARD SHORTCUTS CHEATSHEET'), findsOneWidget);

    // Wait for the cheatsheet overlay timer to finish (3 seconds)
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('KEYBOARD SHORTCUTS CHEATSHEET'), findsNothing);
  });

  testWidgets('Settings screen shortcut toggles settings screen open and closed', (WidgetTester tester) async {
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
        child: const WriterApp(),
      ),
    );

    // Focus the TextField directly via its focusNode to avoid off-screen tap issues
    final TextField textField = tester.widget<TextField>(find.byType(TextField));
    textField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);

    // Open settings
    await pressShortcut(tester, LogicalKeyboardKey.digit4, isSettings: true);

    if (Platform.isMacOS) {
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    } else {
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Close settings
      await pressShortcut(tester, LogicalKeyboardKey.digit4, isSettings: true);
      expect(find.byType(SettingsScreen), findsNothing);
    }
  });

  testWidgets('Settings screen shortcut toggles settings screen open and closed even when search text field has focus', (WidgetTester tester) async {
    when(() => mockSettings.masterDirectoryPath).thenReturn('/test_master');
    when(() => mockSettings.availableProjects).thenReturn([]);

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
        child: const WriterApp(),
      ),
    );

    // Focus the TextField directly via its focusNode to avoid off-screen tap issues
    final TextField editorTextField = tester.widget<TextField>(find.byType(TextField));
    editorTextField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);

    // Open settings
    await pressShortcut(tester, LogicalKeyboardKey.digit4, isSettings: true);

    if (Platform.isMacOS) {
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    } else {
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Find the search TextField on the settings screen and focus it
      final searchFinder = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(TextField),
      ).first;
      await tester.ensureVisible(searchFinder);
      await tester.tap(searchFinder);
      await tester.pumpAndSettle();

      // Verify search text field has focus
      final FocusNode focusNode = Focus.of(tester.element(searchFinder));
      expect(focusNode.hasFocus, isTrue);

      // Close settings
      await pressShortcut(tester, LogicalKeyboardKey.digit4, isSettings: true);

      // Verify SettingsScreen is popped
      expect(find.byType(SettingsScreen), findsNothing);
    }
  });

  testWidgets('NoteEditorDialog Alt+A shortcut toggles note editor dialog closed even when a text field has focus', (WidgetTester tester) async {
    final mockNoteCard = NoteCard(
      id: 'attr-id',
      title: 'Attributions',
      content: 'Attribution Content',
      category: 'general',
      isAttribution: true,
    );
    when(() => mockNotes.cards).thenReturn([mockNoteCard]);
    when(() => mockNotes.addAttributionCard(syncProvider: any(named: 'syncProvider'))).thenAnswer((_) async {});
    registerFallbackValue(DateTime.now());

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
        child: const WriterApp(),
      ),
    );

    // Focus the editor TextField directly via its focusNode to avoid off-screen tap issues
    final TextField editorTextField = tester.widget<TextField>(find.byType(TextField));
    editorTextField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditorDialog), findsNothing);

    // Open attributions
    await pressShortcut(tester, LogicalKeyboardKey.keyA);
    expect(find.byType(NoteEditorDialog), findsOneWidget);

    // Find the title TextField on the dialog and focus it
    final titleFinder = find.descendant(
      of: find.byType(NoteEditorDialog),
      matching: find.byType(TextField),
    ).first;
    await tester.ensureVisible(titleFinder);
    await tester.tap(titleFinder);
    await tester.pumpAndSettle();

    // Verify title text field has focus
    final FocusNode focusNode = Focus.of(tester.element(titleFinder));
    expect(focusNode.hasFocus, isTrue);

    // Close dialog
    await pressShortcut(tester, LogicalKeyboardKey.keyA);

    // Verify NoteEditorDialog is popped
    expect(find.byType(NoteEditorDialog), findsNothing);
  });

  testWidgets('Keyboard shortcuts trigger even when no text field has focus', (WidgetTester tester) async {
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
        child: const WriterApp(),
      ),
    );

    // Verify no text field has focus initially, but the root Focus node is focused
    expect(realShortcuts.isLeftSidebarOpen, isFalse);

    await pressShortcut(tester, LogicalKeyboardKey.digit1);

    expect(realShortcuts.isLeftSidebarOpen, isTrue);
  });

  testWidgets('Settings button and Back button align at the exact same screen coordinates', (WidgetTester tester) async {
    // This test is only applicable on non-macOS platforms where SettingsScreen is used.
    // On macOS, the SettingsScreen is entirely replaced by the native macOS Menu Bar.
    if (Platform.isMacOS) return;

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
        child: const WriterApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Locate the Settings button on the editor status bar and record its coordinates
    final settingsButtonFinder = find.byIcon(Icons.settings);
    expect(settingsButtonFinder, findsOneWidget);
    final Offset settingsPosition = tester.getCenter(settingsButtonFinder);

    // 2. Click the settings button to open the settings screen
    await tester.tap(settingsButtonFinder);
    await tester.pumpAndSettle();

    // 3. Locate the Back button on the settings screen and record its coordinates
    final backButtonFinder = find.byIcon(Icons.arrow_back);
    expect(backButtonFinder, findsOneWidget);
    final Offset backPosition = tester.getCenter(backButtonFinder);

    // 4. Assert that the coordinates are exactly the same
    expect(
      backPosition,
      equals(settingsPosition),
      reason: 'COORDINATE LOCK FAILED: Settings button in Editor and Back button in Settings screen must align at the exact same coordinates to allow instant toggling without mouse movement.',
    );
  });
}
