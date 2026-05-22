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

    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);

    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());

    when(() => mockNotes.cards).thenReturn([]);
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
}
