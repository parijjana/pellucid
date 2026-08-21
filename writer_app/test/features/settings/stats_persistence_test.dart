import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fake_async/fake_async.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late MockSettingsDatabase mockSettingsDatabase;
  late MockStorageService mockStorageService;
  late HistoryProvider historyProvider;

  setUp(() {
    mockSettingsDatabase = MockSettingsDatabase();
    when(() => mockSettingsDatabase.getMirroredProjects()).thenAnswer((_) async => <String>{});
    mockStorageService = MockStorageService();

    when(() => mockSettingsDatabase.getHistory()).thenAnswer((_) async => []);
    when(() => mockSettingsDatabase.upsertHistory(any(), any(), any(), any()))
        .thenAnswer((_) async {});

    registerFallbackValue(ProjectStats());

    when(() => mockStorageService.readProjectStats(any()))
        .thenAnswer((_) async => ProjectStats(totalWordCount: 150, totalTimeSpent: const Duration(seconds: 120)));
    when(() => mockStorageService.saveProjectStats(any(), any()))
        .thenAnswer((_) async {});
  });

  group('HistoryProvider Stats & Persistence', () {
    test('loadProjectStats loads cached stats and resets delta basis', () async {
      historyProvider = HistoryProvider(
        settingsDatabase: mockSettingsDatabase,
        storageService: mockStorageService,
      );
      await historyProvider.loadProjectStats('/test/path');

      expect(historyProvider.currentProjectStats.totalWordCount, 150);
      expect(historyProvider.currentProjectStats.totalTimeSpent.inSeconds, 120);

      // Verify word count updates correctly based on new basis
      historyProvider.updateWordCount(150);
      historyProvider.updateWordCount(200);
      expect(historyProvider.todayStats?.wordCountDelta, 50); // 200 - 150
      expect(historyProvider.currentProjectStats.totalWordCount, 200);
    });

    test('setProjectWordGoal sets and clears the current project goal', () async {
      historyProvider = HistoryProvider(
        settingsDatabase: mockSettingsDatabase,
        storageService: mockStorageService,
      );
      await historyProvider.loadProjectStats('/test/path');

      historyProvider.setProjectWordGoal(5000);
      expect(historyProvider.currentProjectStats.wordGoal, 5000);
      expect(historyProvider.currentProjectStats.hasWordGoal, true);

      // Goal survives a word-count update (copyWith preserves it)
      historyProvider.updateWordCount(300);
      expect(historyProvider.currentProjectStats.wordGoal, 5000);

      // Null clears the goal
      historyProvider.setProjectWordGoal(null);
      expect(historyProvider.currentProjectStats.wordGoal, isNull);
      expect(historyProvider.currentProjectStats.hasWordGoal, false);
    });

    test('Focus tracking increments editor and notes times on tick', () {
      fakeAsync((async) {
        historyProvider = HistoryProvider(
          settingsDatabase: mockSettingsDatabase,
          storageService: mockStorageService,
        );
        historyProvider.loadProjectStats('/test/path');
        
        historyProvider.setEditorFocus(true);
        async.elapse(const Duration(seconds: 5));
        expect(historyProvider.todayStats?.editorTime.inSeconds, 5);
        expect(historyProvider.currentProjectStats.totalTimeSpent.inSeconds, 120 + 5);

        historyProvider.setEditorFocus(false);
        historyProvider.setNotesFocus(true);
        async.elapse(const Duration(seconds: 3));
        expect(historyProvider.todayStats?.notesTime.inSeconds, 3);
        expect(historyProvider.currentProjectStats.totalTimeSpent.inSeconds, 120 + 5 + 3);
      });
    });

    test('saveStatsNow immediately writes to filesystem and DB without database debounce', () async {
      historyProvider = HistoryProvider(
        settingsDatabase: mockSettingsDatabase,
        storageService: mockStorageService,
      );
      await historyProvider.loadProjectStats('/test/path');

      historyProvider.setEditorFocus(true);
      historyProvider.updateWordCount(180);

      await historyProvider.saveStatsNow();

      verify(() => mockStorageService.saveProjectStats('/test/path', any())).called(1);
      verify(() => mockSettingsDatabase.upsertHistory(any(), any(), any(), any())).called(1);
    });
  });
}
