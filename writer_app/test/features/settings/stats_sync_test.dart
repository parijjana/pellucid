import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fake_async/fake_async.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}
class MockStorageService extends Mock implements StorageService {}
class MockSyncProvider extends Mock implements SyncProvider {}

void main() {
  late MockSettingsDatabase mockSettingsDatabase;
  late MockStorageService mockStorageService;
  late MockSyncProvider mockSyncProvider;
  late HistoryProvider historyProvider;

  setUp(() {
    mockSettingsDatabase = MockSettingsDatabase();
    mockStorageService = MockStorageService();
    mockSyncProvider = MockSyncProvider();

    when(() => mockSettingsDatabase.getHistory()).thenAnswer((_) async => []);
    when(() => mockSettingsDatabase.upsertHistory(any(), any(), any(), any()))
        .thenAnswer((_) async {});

    registerFallbackValue(ProjectStats());

    when(() => mockStorageService.readProjectStats(any()))
        .thenAnswer((_) async => ProjectStats(totalWordCount: 150, totalTimeSpent: const Duration(seconds: 120)));
    when(() => mockStorageService.saveProjectStats(any(), any()))
        .thenAnswer((_) async {});
  });

  group('Stats Sync Tests', () {
    test('loadProjectStats pulls remote stats and merges if remote is higher', () async {
      when(() => mockSyncProvider.isLoggedIn).thenReturn(true);
      final remoteStatsJson = jsonEncode(ProjectStats(totalWordCount: 200, totalTimeSpent: const Duration(seconds: 300)).toJson());
      when(() => mockSyncProvider.getLatestContent(projectName: 'path', fileName: 'stats'))
          .thenAnswer((_) async => remoteStatsJson);

      historyProvider = HistoryProvider(
        settingsDatabase: mockSettingsDatabase,
        storageService: mockStorageService,
        syncProvider: mockSyncProvider,
      );

      await historyProvider.loadProjectStats('/test/path');
      // The remote merge now runs in the background (unawaited) so the UI
      // isn't blocked on the network round-trip; flush the event queue to
      // let it complete before asserting on the merged state.
      await pumpEventQueue();

      expect(historyProvider.currentProjectStats.totalWordCount, 200);
      expect(historyProvider.currentProjectStats.totalTimeSpent.inSeconds, 300);

      verify(() => mockStorageService.saveProjectStats('/test/path', any())).called(1);
    });

    test('loadProjectStats does not merge if remote stats are lower', () async {
      when(() => mockSyncProvider.isLoggedIn).thenReturn(true);
      final remoteStatsJson = jsonEncode(ProjectStats(totalWordCount: 100, totalTimeSpent: const Duration(seconds: 50)).toJson());
      when(() => mockSyncProvider.getLatestContent(projectName: 'path', fileName: 'stats'))
          .thenAnswer((_) async => remoteStatsJson);

      historyProvider = HistoryProvider(
        settingsDatabase: mockSettingsDatabase,
        storageService: mockStorageService,
        syncProvider: mockSyncProvider,
      );

      await historyProvider.loadProjectStats('/test/path');
      await pumpEventQueue();

      // remains local values (150 and 120)
      expect(historyProvider.currentProjectStats.totalWordCount, 150);
      expect(historyProvider.currentProjectStats.totalTimeSpent.inSeconds, 120);

      verifyNever(() => mockStorageService.saveProjectStats('/test/path', any()));
    });

    test('saveStatsNow uploads local stats to SyncProvider', () async {
      when(() => mockSyncProvider.isLoggedIn).thenReturn(true);
      when(() => mockSyncProvider.syncStats(projectName: 'path', statsJson: any(named: 'statsJson')))
          .thenAnswer((_) async {});

      historyProvider = HistoryProvider(
        settingsDatabase: mockSettingsDatabase,
        storageService: mockStorageService,
        syncProvider: mockSyncProvider,
      );

      await historyProvider.loadProjectStats('/test/path');
      await historyProvider.saveStatsNow();

      verify(() => mockSyncProvider.syncStats(projectName: 'path', statsJson: any(named: 'statsJson'))).called(1);
    });

    test('autosave uploads local stats to SyncProvider', () {
      fakeAsync((async) {
        when(() => mockSyncProvider.isLoggedIn).thenReturn(true);
        when(() => mockSyncProvider.getLatestContent(projectName: 'path', fileName: 'stats'))
            .thenAnswer((_) async => null);
        when(() => mockSyncProvider.syncStats(projectName: 'path', statsJson: any(named: 'statsJson')))
            .thenAnswer((_) async {});

        historyProvider = HistoryProvider(
          settingsDatabase: mockSettingsDatabase,
          storageService: mockStorageService,
          syncProvider: mockSyncProvider,
        );

        historyProvider.loadProjectStats('/test/path');
        async.elapse(const Duration(milliseconds: 100)); // allow async load to finish
        
        historyProvider.updateWordCount(180);

        async.elapse(const Duration(seconds: 6));

        verify(() => mockSyncProvider.syncStats(projectName: 'path', statsJson: any(named: 'statsJson'))).called(1);
      });
    });
  });
}
