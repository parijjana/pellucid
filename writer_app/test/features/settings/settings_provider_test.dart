// @trace FEAT-20260517-115000-0004
// Description: Unit tests for SettingsProvider (TDD).
// TestID: TEST-20260517-115000-0004

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
      expect(settingsProvider.masterDirectoryPath, '/persisted/path');
      expect(settingsProvider.currentProjectName, 'Old Project');
    });
  });
}
