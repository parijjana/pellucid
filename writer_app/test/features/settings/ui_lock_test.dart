import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/settings/screens/settings_screen.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:provider/provider.dart';

class MockEditorProvider extends Mock implements EditorProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class MockSettingsProvider extends Mock implements SettingsProvider {}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockHistoryProvider extends Mock implements HistoryProvider {}
class MockNotesProvider extends Mock implements NotesProvider {}

void main() {
  late MockEditorProvider mockEditor;
  late MockThemeProvider mockTheme;
  late MockSettingsProvider mockSettings;
  late MockSyncProvider mockSync;
  late MockHistoryProvider mockHistory;
  late MockNotesProvider mockNotes;

  setUp(() {
    mockEditor = MockEditorProvider();
    mockTheme = MockThemeProvider();
    mockSettings = MockSettingsProvider();
    mockSync = MockSyncProvider();
    mockHistory = MockHistoryProvider();
    mockNotes = MockNotesProvider();

    when(() => mockEditor.content).thenReturn('Test content');
    when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets[0]);
    when(() => mockSettings.currentProjectName).thenReturn('Test Project');
    when(() => mockSettings.masterDirectoryPath).thenReturn('/test/path');
    when(() => mockSettings.availableProjects).thenReturn([]);
    when(() => mockSettings.clockEnabled).thenReturn(false);
    when(() => mockSettings.currentSessionEnabled).thenReturn(false);
    when(() => mockSettings.focusTimerEnabled).thenReturn(false);
    when(() => mockSettings.targetSessionEnabled).thenReturn(false);
    
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);
    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    
    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());
    when(() => mockHistory.todayStats).thenReturn(null);

    when(() => mockNotes.cards).thenReturn([]);
  });

  testWidgets('Dashboard UI Lock: Verifies 3 primary sections and their collapsibility', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
          ChangeNotifierProvider<HistoryProvider>.value(value: mockHistory),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    // 1. Verify 'SETUP' section exists and is uppercase
    expect(find.text('SETUP'), findsOneWidget);
    
    // 2. Verify 'PROJECTS' section exists
    expect(find.text('PROJECTS'), findsOneWidget);
    
    // 3. Verify 'STATISTICS' section exists
    expect(find.text('STATISTICS'), findsOneWidget);

    // 4. Verify low-contrast model: Check for presence of collapsible icons
    expect(find.byIcon(Icons.expand_less), findsNWidgets(3));

    // 5. Test Collapsibility
    await tester.tap(find.text('SETUP'));
    await tester.pump();
    expect(find.byIcon(Icons.expand_more), findsOneWidget); // Setup is now collapsed
  });

  testWidgets('Dashboard UI Lock: Verifies specific component placement', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
          ChangeNotifierProvider<HistoryProvider>.value(value: mockHistory),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    // Verify Master Folder Picker is present (part of Setup)
    expect(find.text('MASTER STORAGE FOLDER'), findsOneWidget);
    expect(find.text('FOCUS & PRODUCTIVITY'), findsOneWidget);
    expect(find.text('APPEARANCE'), findsOneWidget);
  });
}
