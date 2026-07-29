// @trace FEAT-20260517-115000-0004
// Description: Unit tests for SettingsProvider (TDD).
// TestID: TEST-20260517-115000-0004

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  late SettingsProvider settingsProvider;
  late MockSettingsDatabase mockSettingsDatabase;
  late MockStorageService mockStorageService;

  setUp(() {
    mockSettingsDatabase = MockSettingsDatabase();
    mockStorageService = MockStorageService();
    
    // Will fail to compile initially.
    settingsProvider = SettingsProvider(
      settingsDatabase: mockSettingsDatabase,
      storageService: mockStorageService,
    );
  });

  group('SettingsProvider', () {
    test('initial values should be correct', () {
      expect(settingsProvider.clockEnabled, false);
      expect(settingsProvider.isWindowFocused, true);
      expect(settingsProvider.batteryGuardEnabled, true);
      expect(settingsProvider.batteryAlertThreshold, 20);
      expect(settingsProvider.showBatteryPercentage, true);
      expect(settingsProvider.syncIntervalMinutes, 30);
    });

    test('toggleClock should update state and database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});
      
      settingsProvider.toggleClock(true);
      
      expect(settingsProvider.clockEnabled, true);
      verify(() => mockSettingsDatabase.updateSetting('clock_enabled', true)).called(1);
    });

    test('toggleBatteryGuard and setBatteryAlertThreshold should update state and database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});
      
      settingsProvider.toggleBatteryGuard(false);
      expect(settingsProvider.batteryGuardEnabled, false);
      verify(() => mockSettingsDatabase.updateSetting('battery_guard_enabled', false)).called(1);

      settingsProvider.setBatteryAlertThreshold(25);
      expect(settingsProvider.batteryAlertThreshold, 25);
      verify(() => mockSettingsDatabase.updateSetting('battery_alert_threshold', 25)).called(1);

      settingsProvider.toggleShowBatteryPercentage(false);
      expect(settingsProvider.showBatteryPercentage, false);
      verify(() => mockSettingsDatabase.updateSetting('show_battery_percentage', false)).called(1);
    });

    test('setMasterDirectory should update state and database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});
      when(() => mockStorageService.initProject(any(), any(), initialContent: any(named: 'initialContent')))
          .thenAnswer((_) async {});
      when(() => mockStorageService.listProjects(any()))
          .thenAnswer((_) async => ['User Manual']);
      when(() => mockStorageService.readProjectStats(any()))
          .thenAnswer((_) async => ProjectStats(totalWordCount: 0, totalTimeSpent: Duration.zero));
      
      await settingsProvider.setMasterDirectory('/test/path');
      
      expect(settingsProvider.masterDirectoryPath, '/test/path');
      verify(() => mockSettingsDatabase.updateSetting('master_directory_path', '/test/path')).called(1);
    });

    test('setCurrentProject should update state and database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});
      
      await settingsProvider.setCurrentProject('My Project');
      
      expect(settingsProvider.currentProjectName, 'My Project');
      verify(() => mockSettingsDatabase.updateSetting('current_project_name', 'My Project')).called(1);
    });

    test('loadSettings should populate settings from database', () async {
      when(() => mockSettingsDatabase.getSettings()).thenAnswer((_) async => {
        'clock_enabled': 1,
        'current_session_enabled': 0,
        'target_session_enabled': 0,
        'focus_timer_enabled': 1,
        'battery_guard_enabled': 0,
        'battery_alert_threshold': 15,
        'show_battery_percentage': 0,
        'master_directory_path': '/persisted/path',
        'current_project_name': 'Old Project',
        'sync_interval_minutes': 15,
      });
      when(() => mockStorageService.initProject(any(), any(), initialContent: any(named: 'initialContent')))
          .thenAnswer((_) async {});
      when(() => mockStorageService.listProjects(any()))
          .thenAnswer((_) async => ['Old Project', 'User Manual']);
      when(() => mockStorageService.readProjectStats(any()))
          .thenAnswer((_) async => ProjectStats(totalWordCount: 100, totalTimeSpent: Duration.zero));

      await settingsProvider.loadSettings();

      expect(settingsProvider.clockEnabled, true);
      expect(settingsProvider.focusTimerEnabled, true);
      expect(settingsProvider.batteryGuardEnabled, false);
      expect(settingsProvider.batteryAlertThreshold, 15);
      expect(settingsProvider.showBatteryPercentage, false);
      // App Sandbox migration (DB v14 -> v15): a `master_directory_path` that was
      // persisted (e.g. by a pre-sandbox build) with no accompanying
      // `master_directory_bookmark` grants no filesystem access under the macOS
      // App Sandbox. loadSettings treats that as unusable and nulls the path so
      // the UI prompts the user to re-select the folder (which mints a fresh
      // security-scoped bookmark). On non-macOS platforms there is no sandbox
      // bookmark requirement, so the persisted raw path loads unchanged.
      if (Platform.isMacOS) {
        expect(settingsProvider.masterDirectoryPath, isNull);
      } else {
        expect(settingsProvider.masterDirectoryPath, '/persisted/path');
      }
      expect(settingsProvider.currentProjectName, 'Old Project');
      expect(settingsProvider.syncIntervalMinutes, 15);
    });

    test('tocWordCountsEnabled defaults to true', () {
      expect(settingsProvider.tocWordCountsEnabled, true);
    });

    test('toggleTocWordCounts should update state and database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});

      settingsProvider.toggleTocWordCounts(false);
      expect(settingsProvider.tocWordCountsEnabled, false);
      verify(() => mockSettingsDatabase.updateSetting('toc_word_counts_enabled', false)).called(1);

      settingsProvider.toggleTocWordCounts(true);
      expect(settingsProvider.tocWordCountsEnabled, true);
      verify(() => mockSettingsDatabase.updateSetting('toc_word_counts_enabled', true)).called(1);
    });

    test('loadSettings reads toc_word_counts_enabled', () async {
      when(() => mockSettingsDatabase.getSettings()).thenAnswer((_) async => {
        'toc_word_counts_enabled': 0,
      });
      when(() => mockStorageService.initProject(any(), any(), initialContent: any(named: 'initialContent')))
          .thenAnswer((_) async {});
      when(() => mockStorageService.listProjects(any()))
          .thenAnswer((_) async => ['User Manual']);
      when(() => mockStorageService.readProjectStats(any()))
          .thenAnswer((_) async => ProjectStats(totalWordCount: 0, totalTimeSpent: Duration.zero));

      await settingsProvider.loadSettings();

      expect(settingsProvider.tocWordCountsEnabled, false);
    });

    test('dailyWordGoal defaults to 0 (off)', () {
      expect(settingsProvider.dailyWordGoal, 0);
      expect(settingsProvider.hasDailyWordGoal, false);
    });

    test('setDailyWordGoal should update state and database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});

      settingsProvider.setDailyWordGoal(500);
      expect(settingsProvider.dailyWordGoal, 500);
      expect(settingsProvider.hasDailyWordGoal, true);
      verify(() => mockSettingsDatabase.updateSetting('daily_word_goal', 500)).called(1);

      settingsProvider.setDailyWordGoal(0);
      expect(settingsProvider.dailyWordGoal, 0);
      expect(settingsProvider.hasDailyWordGoal, false);
      verify(() => mockSettingsDatabase.updateSetting('daily_word_goal', 0)).called(1);
    });

    test('setDailyWordGoal clamps negatives to 0', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});

      settingsProvider.setDailyWordGoal(-100);
      expect(settingsProvider.dailyWordGoal, 0);
    });

    test('loadSettings reads daily_word_goal', () async {
      when(() => mockSettingsDatabase.getSettings()).thenAnswer((_) async => {
        'daily_word_goal': 1000,
      });
      when(() => mockStorageService.initProject(any(), any(), initialContent: any(named: 'initialContent')))
          .thenAnswer((_) async {});
      when(() => mockStorageService.listProjects(any()))
          .thenAnswer((_) async => ['User Manual']);
      when(() => mockStorageService.readProjectStats(any()))
          .thenAnswer((_) async => ProjectStats(totalWordCount: 0, totalTimeSpent: Duration.zero));

      await settingsProvider.loadSettings();

      expect(settingsProvider.dailyWordGoal, 1000);
      expect(settingsProvider.hasDailyWordGoal, true);
    });

    test('setGoogleCredentials should update state and database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});

      await settingsProvider.setGoogleCredentials('my-client-id', 'my-client-secret');

      expect(settingsProvider.googleClientId, 'my-client-id');
      expect(settingsProvider.googleClientSecret, 'my-client-secret');
      verify(() => mockSettingsDatabase.updateSetting('google_client_id', 'my-client-id')).called(1);
      verify(() => mockSettingsDatabase.updateSetting('google_client_secret', 'my-client-secret')).called(1);
    });

    test('updateSyncInterval should update state and database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});

      await settingsProvider.updateSyncInterval(60);

      expect(settingsProvider.syncIntervalMinutes, 60);
      verify(() => mockSettingsDatabase.updateSetting('sync_interval_minutes', 60)).called(1);
    });
  });
}
