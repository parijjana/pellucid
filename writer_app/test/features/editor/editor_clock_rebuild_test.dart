import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/list_marker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_font.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';
import 'package:pellucid/features/editor/widgets/session_timer_widget.dart';
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
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/sync/services/token_store.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:window_manager/window_manager.dart';

class _Db extends Mock implements SettingsDatabase {
  @override
  Future<void> updateSetting(String key, dynamic value) async {}
}
class MockStorageService extends Mock implements StorageService {}
class _Secrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}
class MockEditorProvider extends Mock implements EditorProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class _UnusedMockSettings extends Mock implements SettingsProvider {
  @override
  EditorFont get editorFont => EditorFont.defaultFont;
  @override
  bool get spellCheckEnabled => true;
  @override
  bool get grammarHintsEnabled => false;
  @override
  bool get smartPunctuationEnabled => false;
  @override
  BulletStyle get bulletStyle => BulletStyle.defaultStyle;
  @override
  bool get autoContinueListsEnabled => true;
  @override
  bool get attributionDuplicateHighlightEnabled => true;
}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockHistoryProvider extends Mock implements HistoryProvider {}
class MockNotesProvider extends Mock implements NotesProvider {}
class MockWindowManager extends Mock implements WindowManager {}

void main() {
  late MockEditorProvider mockEditor;
  late MockThemeProvider mockTheme;
  late SettingsProvider settings;
  late MockSyncProvider mockSync;
  late MockHistoryProvider mockHistory;
  late MockNotesProvider mockNotes;

  setUp(() {
    mockEditor = MockEditorProvider();
    mockTheme = MockThemeProvider();

    mockSync = MockSyncProvider();
    mockHistory = MockHistoryProvider();
    mockNotes = MockNotesProvider();

    when(() => mockEditor.content).thenReturn('# Hello World');

    when(() => mockEditor.documentLoadFailed).thenReturn(false);

    when(() => mockEditor.isMirrorProject).thenReturn(false);
    when(() => mockEditor.zoomLevel).thenReturn(1.0);
    when(() => mockEditor.pageWidth).thenReturn(800.0);
    when(() => mockEditor.horizontalPosition).thenReturn(0.5);
    
    when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets[0]);
    

    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);

    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());

    when(() => mockNotes.cards).thenReturn([]);
  });

  testWidgets('a clock tick rebuilds only the status-bar clock, not EditorScreen', (tester) async {
    settings = SettingsProvider(
      settingsDatabase: _Db(),
      storageService: MockStorageService(),
      tokenStore: TokenStore(secrets: _Secrets(), prefs: SharedPreferences.getInstance),
    );
    settings.toggleCurrentSession(true);
    var settingsNotifies = 0;
    settings.addListener(() => settingsNotifies++);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
          ChangeNotifierProvider<HistoryProvider>.value(value: mockHistory),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
          ChangeNotifierProvider<SearchProvider>(create: (_) => SearchProvider()),
          ChangeNotifierProvider<ShortcutsProvider>(create: (_) => ShortcutsProvider()),
          ChangeNotifierProvider<SprintController>(create: (_) => SprintController()),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pump();
    final builds = editorScreenBuildCount;
    final before = settings.currentSessionTime;
    final label = find.byType(SessionTimerWidget);
    expect(label, findsOneWidget);
    final textBefore = tester.widget<SessionTimerWidget>(label).current;

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(editorScreenBuildCount, builds, reason: 'EditorScreen must not rebuild on ticks');
    expect(settingsNotifies, 0, reason: 'ticks must not notify SettingsProvider');
    expect(settings.currentSessionTime - before, const Duration(seconds: 5));
    expect(tester.widget<SessionTimerWidget>(label).current - textBefore, const Duration(seconds: 5));

    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
