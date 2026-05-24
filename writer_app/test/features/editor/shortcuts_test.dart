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
import 'package:pellucid/features/sidebar/providers/note_card.dart';
import 'package:pellucid/features/sidebar/widgets/note_editor_dialog.dart';
import 'package:pellucid/features/editor/widgets/alarm_setter_dialog.dart';
import 'package:pellucid/features/settings/screens/settings_screen.dart';
import 'package:pellucid/main.dart';
import 'package:provider/provider.dart';

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
    when(() => mockSettings.clockEnabled).thenReturn(false);
    when(() => mockSettings.currentSessionEnabled).thenReturn(false);
    when(() => mockSettings.targetSessionEnabled).thenReturn(false);
    when(() => mockSettings.focusTimerEnabled).thenReturn(false);
    when(() => mockSettings.isAlarmTriggered).thenReturn(false);
    when(() => mockSettings.batteryGuardEnabled).thenReturn(false);
    when(() => mockSettings.batteryAlertThreshold).thenReturn(20);
    when(() => mockSettings.lastNotesFullscreenState).thenReturn(false);
    when(() => mockSettings.setLastNotesFullscreenState(any())).thenAnswer((_) async {});

    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);

    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());

    when(() => mockNotes.cards).thenReturn([]);
    when(() => mockNotes.categories).thenReturn(['general', 'people', 'places', 'events']);
  });

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
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
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

    // 1. Toggle Left Sidebar (Alt + 1)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(realShortcuts.isLeftSidebarOpen, isTrue);

    // 2. Toggle Right Sidebar (Alt + 2)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(realShortcuts.isRightSidebarOpen, isTrue);

    // 3. Toggle Floating Toolbar (Alt + 3)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(realShortcuts.isToolbarOpen, isTrue);

    // 4. Toggle Fullscreen (Alt + Enter)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(realShortcuts.isFullscreen, isTrue);

    // 5. Peek Clock (Alt + C)
    expect(realShortcuts.isClockPeeked, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(realShortcuts.isClockPeeked, isTrue);

    // 6. Peek Session (Alt + S)
    expect(realShortcuts.isSessionPeeked, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(realShortcuts.isSessionPeeked, isTrue);

    // Let the 2-second peek timers complete so we do not have pending timers on teardown
    await tester.pump(const Duration(seconds: 2));
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
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
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
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
        ],
        child: const WriterApp(),
      ),
    );

    // Focus the TextField directly
    final TextField textField = tester.widget<TextField>(find.byType(TextField));
    textField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    // Test Alt + Shift + A (SetAlarmIntent)
    // Press Alt + Shift + A
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // Verify that AlarmSetterDialog is opened
    expect(find.byType(AlarmSetterDialog), findsOneWidget);

    // Close the dialog using Escape key
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlarmSetterDialog), findsNothing);

    // Test Alt + A (OpenAttributionIntent)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // Verify that NoteEditorDialog is opened
    expect(find.byType(NoteEditorDialog), findsOneWidget);

    // Close the note dialog using Alt + A
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
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
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
        ],
        child: const WriterApp(),
      ),
    );

    // Focus the TextField directly via its focusNode to avoid off-screen tap issues
    final TextField textField = tester.widget<TextField>(find.byType(TextField));
    textField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);

    // Press Alt + 4 to open settings
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);

    // Press Alt + 4 again to close settings
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
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
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
        ],
        child: const WriterApp(),
      ),
    );

    // Focus the TextField directly via its focusNode to avoid off-screen tap issues
    final TextField editorTextField = tester.widget<TextField>(find.byType(TextField));
    editorTextField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);

    // Press Alt + 4 to open settings
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

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

    // Press Alt + 4 again to close settings
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // Verify SettingsScreen is popped
    expect(find.byType(SettingsScreen), findsNothing);
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
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
        ],
        child: const WriterApp(),
      ),
    );

    // Focus the editor TextField directly via its focusNode to avoid off-screen tap issues
    final TextField editorTextField = tester.widget<TextField>(find.byType(TextField));
    editorTextField.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditorDialog), findsNothing);

    // Press Alt + A to open attributions
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

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

    // Press Alt + A again to close dialog
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

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
          ChangeNotifierProvider<ShortcutsProvider>.value(value: realShortcuts),
        ],
        child: const WriterApp(),
      ),
    );

    // Verify no text field has focus initially, but the root Focus node is focused
    expect(realShortcuts.isLeftSidebarOpen, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(realShortcuts.isLeftSidebarOpen, isTrue);
  });
}
