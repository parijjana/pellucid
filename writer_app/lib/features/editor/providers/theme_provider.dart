// @trace FEAT-20260516-115000-0003
// Description: Expanded Model for Writer Themes and ThemeProvider (Persistent).

import 'package:flutter/material.dart';
import '../../settings/providers/settings_database.dart';

class WriterTheme {
  final String name;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color sidebarColor;
  final List<BoxShadow> sidebarShadows;
  final double noiseOpacity;

  const WriterTheme({
    required this.name,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.sidebarColor,
    this.sidebarShadows = const [
      BoxShadow(
        color: Color(0x0D000000),
        blurRadius: 15,
        offset: Offset(0, 0),
      ),
    ],
    this.noiseOpacity = 0.0,
  });

  static final List<WriterTheme> presets = [
    WriterTheme(
      name: 'Paper',
      backgroundColor: Color(0xFFF9F7F2),
      foregroundColor: Color(0xFF222222),
      sidebarColor: Color(0xFFF9F7F2),
    ),
    WriterTheme(
      name: 'Midnight',
      backgroundColor: Color(0xFF0F111A),
      foregroundColor: Color(0xFFE3E3E3),
      sidebarColor: Color(0xFF0F111A),
      sidebarShadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
        ),
      ],
    ),
    WriterTheme(
      name: 'Sepia',
      backgroundColor: Color(0xFFF4ECD8),
      foregroundColor: Color(0xFF433422),
      sidebarColor: Color(0xFFF4ECD8),
    ),
    WriterTheme(
      name: 'Forest',
      backgroundColor: Color(0xFF121A16),
      foregroundColor: Color(0xFFC9D1C9),
      sidebarColor: Color(0xFF121A16),
    ),
    WriterTheme(
      name: 'Solarized Light',
      backgroundColor: Color(0xFFFDF6E3),
      foregroundColor: Color(0xFF586E75),
      sidebarColor: Color(0xFFFDF6E3),
    ),
    WriterTheme(
      name: 'Solarized Dark',
      backgroundColor: Color(0xFF002B36),
      foregroundColor: Color(0xFF839496),
      sidebarColor: Color(0xFF002B36),
    ),
    WriterTheme(
      name: 'Dracula',
      backgroundColor: Color(0xFF282A36),
      foregroundColor: Color(0xFFF8F8F2),
      sidebarColor: Color(0xFF282A36),
    ),
    WriterTheme(
      name: 'Nord',
      backgroundColor: Color(0xFF2E3440),
      foregroundColor: Color(0xFFD8DEE9),
      sidebarColor: Color(0xFF2E3440),
    ),
    WriterTheme(
      name: 'Cyberpunk',
      backgroundColor: Color(0xFF000B1E),
      foregroundColor: Color(0xFF00FF9F),
      sidebarColor: Color(0xFF000B1E),
      sidebarShadows: [
        BoxShadow(
          color: const Color(0xFF00FF9F).withValues(alpha: 0.1),
          blurRadius: 20,
        ),
      ],
    ),
  ];
}

class ThemeProvider extends ChangeNotifier {
  final SettingsDatabase _db;
  WriterTheme _currentTheme = WriterTheme.presets[0];

  ThemeProvider({SettingsDatabase? settingsDatabase}) 
      : _db = settingsDatabase ?? SettingsDatabase.instance;

  WriterTheme get currentTheme => _currentTheme;

  Future<void> loadSettings() async {
    final settings = await _db.getSettings();
    final themeName = settings['theme_name'];
    _currentTheme = WriterTheme.presets.firstWhere(
      (t) => t.name == themeName,
      orElse: () => WriterTheme.presets[0],
    );
    notifyListeners();
  }

  void setTheme(WriterTheme theme) {
    _currentTheme = theme;
    _db.updateSetting('theme_name', theme.name);
    notifyListeners();
  }
}
