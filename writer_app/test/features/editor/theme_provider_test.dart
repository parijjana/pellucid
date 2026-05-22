// @trace FEAT-20260516-115000-0003
// Description: Unit tests for ThemeProvider (TDD).
// TestID: TEST-20260516-115000-0003

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  late ThemeProvider themeProvider;
  late MockSettingsDatabase mockSettingsDatabase;

  setUp(() {
    mockSettingsDatabase = MockSettingsDatabase();
    
    // Will fail to compile: ThemeProvider doesn't accept settingsDatabase yet.
    themeProvider = ThemeProvider(settingsDatabase: mockSettingsDatabase);
  });

  group('ThemeProvider', () {
    test('initial theme should be Paper', () {
      expect(themeProvider.currentTheme.name, 'Paper');
    });

    test('setTheme should update theme and settings database', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});
      
      final midnight = WriterTheme.presets.firstWhere((t) => t.name == 'Midnight');
      
      themeProvider.setTheme(midnight);
      
      expect(themeProvider.currentTheme.name, 'Midnight');
      verify(() => mockSettingsDatabase.updateSetting('theme_name', 'Midnight')).called(1);
    });

    test('loadSettings should load theme from database', () async {
      when(() => mockSettingsDatabase.getSettings()).thenAnswer((_) async => {
        'theme_name': 'Sepia',
      });

      await themeProvider.loadSettings();
      
      expect(themeProvider.currentTheme.name, 'Sepia');
    });
  });
}
