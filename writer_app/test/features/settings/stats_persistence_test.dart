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

    test('persistence is throttled to 30 s while focused, and flushed on blur with no lost seconds', () {
      fakeAsync((async) {
        historyProvider = HistoryProvider(
          settingsDatabase: mockSettingsDatabase,
          storageService: mockStorageService,
        );
        historyProvider.loadProjectStats('/test/path');
        async.flushMicrotasks();
        clearInteractions(mockSettingsDatabase);
        clearInteractions(mockStorageService);

        historyProvider.setEditorFocus(true);
        async.elapse(const Duration(seconds: 29));
        verifyNever(() => mockSettingsDatabase.upsertHistory(any(), any(), any(), any()));
        verifyNever(() => mockStorageService.saveProjectStats(any(), any()));

        // The 30 s window opens at the first tick (t=1), so it closes at t=31.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        verify(() => mockSettingsDatabase.upsertHistory(any(), 31, 0, 0)).called(1);
        verify(() => mockStorageService.saveProjectStats('/test/path', any())).called(1);

        // 7 more seconds, then blur: written immediately, nothing lost.
        async.elapse(const Duration(seconds: 7));
        verifyNever(() => mockSettingsDatabase.upsertHistory(any(), 38, any(), any()));
        historyProvider.setEditorFocus(false);
        async.flushMicrotasks();
        verify(() => mockSettingsDatabase.upsertHistory(any(), 38, 0, 0)).called(1);
        final saved = verify(() => mockStorageService.saveProjectStats('/test/path', captureAny())).captured;
        expect((saved.last as ProjectStats).totalTimeSpent.inSeconds, 120 + 38);

        // Ticks never notify listeners.
        var notified = 0;
        historyProvider.addListener(() => notified++);
        historyProvider.setEditorFocus(true);
        async.elapse(const Duration(seconds: 5));
        expect(notified, 0);
        expect(historyProvider.editorTimeToday.value.inSeconds, 43);
        historyProvider.setEditorFocus(false);
        async.flushMicrotasks();
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
