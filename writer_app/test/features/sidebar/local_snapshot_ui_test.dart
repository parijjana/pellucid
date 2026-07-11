// Description: Widget tests for the Local Snapshot Safety Net UI
// (LocalSnapshotList, SnapshotManagementDialog tabs, local-mode RevisionPreviewDialog).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/local_snapshot_store.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sidebar/widgets/local_snapshot_list.dart';
import 'package:pellucid/features/sidebar/widgets/revision_preview_dialog.dart';
import 'package:pellucid/features/sidebar/widgets/snapshot_management_dialog.dart';
import 'package:pellucid/features/sidebar/widgets/snapshot_tab_toggle.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';

class MockStorageService extends Mock implements StorageService {}
class MockSettingsProvider extends Mock implements SettingsProvider {}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  final theme = WriterTheme.presets.first;
  late MockStorageService mockStorage;
  late MockSettingsProvider mockSettings;
  late MockSyncProvider mockSync;
  late MockThemeProvider mockTheme;

  setUp(() {
    mockStorage = MockStorageService();
    mockSettings = MockSettingsProvider();
    mockSync = MockSyncProvider();
    mockTheme = MockThemeProvider();

    when(() => mockTheme.currentTheme).thenReturn(theme);
    when(() => mockSync.isLoggedIn).thenReturn(false);
  });

  group('LocalSnapshotList', () {
    testWidgets('renders snapshot rows with date/time and word count', (tester) async {
      when(() => mockStorage.listLocalSnapshots('/master/Alpha')).thenAnswer((_) async => [
            LocalSnapshotRecord(
              timestamp: DateTime(2026, 7, 4, 15, 30),
              filePath: '/master/Alpha/.history/2026-07-04T15-30-00.md',
            ),
            LocalSnapshotRecord(
              timestamp: DateTime(2026, 7, 3, 9, 5),
              filePath: '/master/Alpha/.history/2026-07-03T09-05-00.md',
            ),
          ]);
      when(() => mockStorage.readLocalSnapshot('/master/Alpha/.history/2026-07-04T15-30-00.md'))
          .thenAnswer((_) async => 'one two three');
      when(() => mockStorage.readLocalSnapshot('/master/Alpha/.history/2026-07-03T09-05-00.md'))
          .thenAnswer((_) async => 'hello world');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalSnapshotList(
              projectPath: '/master/Alpha',
              projectName: 'Alpha',
              theme: theme,
              storageService: mockStorage,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('7/4 15:30'), findsOneWidget);
      expect(find.text('3 words'), findsOneWidget);
      expect(find.text('7/3 09:05'), findsOneWidget);
      expect(find.text('2 words'), findsOneWidget);
    });

    testWidgets('renders empty state when no snapshots exist', (tester) async {
      when(() => mockStorage.listLocalSnapshots(any())).thenAnswer((_) async => []);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalSnapshotList(
              projectPath: '/master/Alpha',
              projectName: 'Alpha',
              theme: theme,
              storageService: mockStorage,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No local snapshots yet'), findsOneWidget);
    });
  });

  group('SnapshotManagementDialog', () {
    testWidgets('defaults to Local tab when logged out and switches tabs on tap', (tester) async {
      when(() => mockSettings.masterDirectoryPath).thenReturn(null);
      when(() => mockSettings.currentProjectName).thenReturn('Alpha');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ],
          child: const MaterialApp(
            home: SnapshotManagementDialog(projectName: 'Alpha'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Toggle rendered; defaults to Local because Drive is not connected.
      expect(find.byType(SnapshotTabToggle), findsOneWidget);
      expect(find.byType(LocalSnapshotList), findsOneWidget);

      // Switch to Cloud: local list disappears, logged-out cloud message appears.
      await tester.tap(find.text('Cloud'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalSnapshotList), findsNothing);
      expect(find.textContaining('Connect to Google Drive'), findsOneWidget);

      // Switch back to Local.
      await tester.tap(find.text('Local'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalSnapshotList), findsOneWidget);
    });
  });

  group('RevisionPreviewDialog (local mode)', () {
    late EditorProvider editorProvider;

    setUp(() {
      editorProvider = EditorProvider(
        storageService: mockStorage,
        settingsDatabase: MockSettingsDatabase(),
      );
      // No project loaded, so this only sets in-memory content (no timers).
      editorProvider.updateContent('one two three four');

      when(() => mockStorage.readLocalSnapshot('/master/Alpha/.history/2026-07-04T15-30-00.md'))
          .thenAnswer((_) async => 'restored words here');
      when(() => mockSettings.masterDirectoryPath).thenReturn('/master');
    });

    Future<void> pumpPreviewDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<EditorProvider>.value(value: editorProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => RevisionPreviewDialog(
                      projectName: 'Alpha',
                      fileName: 'manuscript.md',
                      displayTime: '7/4 15:30',
                      localFilePath: '/master/Alpha/.history/2026-07-04T15-30-00.md',
                      storageService: mockStorage,
                    ),
                  ),
                  child: const Text('open preview'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open preview'));
      await tester.pumpAndSettle();
    }

    testWidgets('loads local content, shows word count + delta, and restores into the active editor without cloud calls', (tester) async {
      when(() => mockSettings.currentProjectName).thenReturn('Alpha');

      await pumpPreviewDialog(tester);

      // Content loaded via readLocalSnapshot: 3 words vs 4 currently in the editor.
      expect(find.text('Preview Snapshot - 7/4 15:30'), findsOneWidget);
      expect(find.text('restored words here'), findsOneWidget);
      expect(find.text('3 words (-1 relative to current)'), findsOneWidget);

      await tester.tap(find.text('Restore Version'));
      await tester.pumpAndSettle();
      expect(find.text('Restore Snapshot?'), findsOneWidget);
      expect(find.text('This will overwrite your current active manuscript.'), findsOneWidget);

      await tester.tap(find.text('Confirm Restore'));
      await tester.pumpAndSettle();

      // Active project: restored content routed into the live editor.
      expect(editorProvider.content, 'restored words here');

      // Local restore must not touch the cloud.
      verifyNever(() => mockSync.syncCurrentFile(
            projectName: any(named: 'projectName'),
            fileName: any(named: 'fileName'),
            content: any(named: 'content'),
          ));
      verifyNever(() => mockSync.loadHistory(any(), any()));
    });

    testWidgets('restores an inactive project by overwriting document.md on disk', (tester) async {
      when(() => mockSettings.currentProjectName).thenReturn('OtherProject');
      when(() => mockStorage.saveDocument(any(), any())).thenAnswer((_) async {});

      await pumpPreviewDialog(tester);

      await tester.tap(find.text('Restore Version'));
      await tester.pumpAndSettle();
      expect(find.text('This will overwrite the manuscript for project "Alpha".'), findsOneWidget);

      await tester.tap(find.text('Confirm Restore'));
      await tester.pumpAndSettle();

      // Inactive project: written to disk, live editor untouched.
      verify(() => mockStorage.saveDocument('/master/Alpha', 'restored words here')).called(1);
      expect(editorProvider.content, 'one two three four');

      verifyNever(() => mockSync.syncCurrentFile(
            projectName: any(named: 'projectName'),
            fileName: any(named: 'fileName'),
            content: any(named: 'content'),
          ));
      verifyNever(() => mockSync.loadHistory(any(), any()));
    });
  });
}
