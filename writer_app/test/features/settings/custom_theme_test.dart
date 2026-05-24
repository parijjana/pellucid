import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  late MockSettingsDatabase mockSettingsDatabase;
  late ThemeProvider themeProvider;

  setUp(() {
    mockSettingsDatabase = MockSettingsDatabase();
  });

  group('Custom Theme Encoding/Decoding Tests', () {
    test('ThemeProvider loads custom encoded theme from database', () async {
      when(() => mockSettingsDatabase.getSettings()).thenAnswer((_) async => {
        'theme_name': 'custom_0xFF123456_0xFFABCDEF',
      });

      themeProvider = ThemeProvider(settingsDatabase: mockSettingsDatabase);
      await themeProvider.loadSettings();

      expect(themeProvider.currentTheme.name, 'Custom');
      expect(themeProvider.currentTheme.backgroundColor.value, 0xFF123456);
      expect(themeProvider.currentTheme.foregroundColor.value, 0xFFABCDEF);
    });

    test('ThemeProvider saves custom theme by encoding colors', () async {
      when(() => mockSettingsDatabase.updateSetting('theme_name', any()))
          .thenAnswer((_) async {});

      themeProvider = ThemeProvider(settingsDatabase: mockSettingsDatabase);

      final customTheme = const WriterTheme(
        name: 'Custom',
        backgroundColor: Color(0xFF112233),
        foregroundColor: Color(0xFF445566),
        sidebarColor: Color(0xFF112233),
      );

      themeProvider.setTheme(customTheme);

      expect(themeProvider.currentTheme.name, 'Custom');
      verify(() => mockSettingsDatabase.updateSetting('theme_name', 'custom_0xff112233_0xff445566')).called(1);
    });
  });
}
