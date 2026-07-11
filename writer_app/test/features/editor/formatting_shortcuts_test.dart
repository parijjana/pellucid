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
}
