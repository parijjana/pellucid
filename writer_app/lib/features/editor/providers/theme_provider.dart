// @trace FEAT-20260516-115000-0003
// Description: Expanded Model for Writer Themes and ThemeProvider (Persistent).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    WriterTheme(
      name: 'Sakura',
      backgroundColor: Color(0xFFFFF5F6),
      foregroundColor: Color(0xFF5C2C35),
      sidebarColor: Color(0xFFFFF5F6),
    ),
    WriterTheme(
      name: 'Matrix',
      backgroundColor: Color(0xFF000000),
      foregroundColor: Color(0xFF39FF14),
      sidebarColor: Color(0xFF000000),
    ),
    WriterTheme(
      name: 'Aura',
      backgroundColor: Color(0xFF1A1B26),
      foregroundColor: Color(0xFFC0CAF5),
      sidebarColor: Color(0xFF16161E),
    ),
    WriterTheme(
      name: 'Mocha',
      backgroundColor: Color(0xFFFAF0E6),
      foregroundColor: Color(0xFF4E3629),
      sidebarColor: Color(0xFFFAF0E6),
    ),
  ];

  static const List<WriterTheme> macMatchedPresets = [
    WriterTheme(
      name: 'Macbook Air/Pro: Midnight',
      backgroundColor: Color(0xFF111622),
      foregroundColor: Color(0xFFE3E3E6),
      sidebarColor: Color(0xFF151E2E),
    ),
    WriterTheme(
      name: 'Macbook Air/Pro: Space Gray',
      backgroundColor: Color(0xFF2D2F34),
      foregroundColor: Color(0xFFF5F5F7),
      sidebarColor: Color(0xFF27282C),
    ),
    WriterTheme(
      name: 'Macbook Air/Pro: Space Black',
      backgroundColor: Color(0xFF1C1C1E),
      foregroundColor: Color(0xFFD1D1D6),
      sidebarColor: Color(0xFF121214),
    ),
    WriterTheme(
      name: 'Macbook Air/Pro: Silver',
      backgroundColor: Color(0xFFE5E5E7),
      foregroundColor: Color(0xFF1D1D1F),
      sidebarColor: Color(0xFFDDDDDF),
    ),
    WriterTheme(
      name: 'Macbook Air/Pro: Starlight',
      backgroundColor: Color(0xFFF2ECDC),
      foregroundColor: Color(0xFF2F3032),
      sidebarColor: Color(0xFFEADEC6),
    ),
    WriterTheme(
      name: 'Macbook Neo: Citrus',
      backgroundColor: Color(0xFFFFF9E6),
      foregroundColor: Color(0xFF4A3E1B),
      sidebarColor: Color(0xFFFFF4CD),
    ),
    WriterTheme(
      name: 'Macbook Neo: Blush',
      backgroundColor: Color(0xFFFFF0F2),
      foregroundColor: Color(0xFF5C2C35),
      sidebarColor: Color(0xFFFFE3E6),
    ),
    WriterTheme(
      name: 'Macbook Neo: Indigo',
      backgroundColor: Color(0xFF1A1D2E),
      foregroundColor: Color(0xFFD2D6E8),
      sidebarColor: Color(0xFF141726),
    ),
  ];
}

class ThemeProvider extends ChangeNotifier {
  final SettingsDatabase _db;
  WriterTheme _currentTheme = WriterTheme.presets[0];
  String _macColorName = 'Space Gray';
  WriterTheme? _macMatchedTheme;

  ThemeProvider({SettingsDatabase? settingsDatabase}) 
      : _db = settingsDatabase ?? SettingsDatabase.instance;

  WriterTheme get currentTheme => _currentTheme;
  String get macColorName => _macColorName;
  WriterTheme? get macMatchedTheme => _macMatchedTheme;

  static const _channel = MethodChannel('com.overengineeredhobbies.pellucid/hardware');

  Future<void> detectMacColor() async {
    if (!Platform.isMacOS || Platform.environment.containsKey('FLUTTER_TEST')) {
      _parseHousingColor('unknown', false);
      return;
    }
    try {
      final Map? info = await _channel.invokeMethod<Map>('getMacHardwareInfo');
      if (info != null) {
        final model = (info['model'] as String? ?? '').toLowerCase();
        final hexColor = info['housingColor'] as String? ?? 'unknown';
        final isAir = model.contains('macbookair') || 
                      model.contains('macbook air') || 
                      model.contains('mac14,2') || 
                      model.contains('mac14,15') || 
                      model.contains('mac15,12') || 
                      model.contains('mac15,13') || 
                      model.contains('mac16,13') || 
                      model.contains('air');
        _parseHousingColor(hexColor, isAir);
        return;
      }
    } catch (_) {}
    _parseHousingColor('unknown', false);
  }

  void _parseHousingColor(String hex, bool isAir) {
    if (hex.endsWith('07000000')) {
      if (isAir) {
        _macColorName = 'Midnight';
        _macMatchedTheme = const WriterTheme(
          name: 'Match My Mac (Midnight)',
          backgroundColor: Color(0xFF111622),
          foregroundColor: Color(0xFFE3E3E6),
          sidebarColor: Color(0xFF151E2E),
        );
      } else {
        _macColorName = 'Space Gray';
        _macMatchedTheme = const WriterTheme(
          name: 'Match My Mac (Space Gray)',
          backgroundColor: Color(0xFF2D2F34),
          foregroundColor: Color(0xFFF5F5F7),
          sidebarColor: Color(0xFF27282C),
        );
      }
    } else if (hex.endsWith('01000000')) {
      _macColorName = 'Silver';
      _macMatchedTheme = const WriterTheme(
        name: 'Match My Mac (Silver)',
        backgroundColor: Color(0xFFE5E5E7),
        foregroundColor: Color(0xFF1D1D1F),
        sidebarColor: Color(0xFFDDDDDF),
      );
    } else if (hex.endsWith('08000000') || hex.contains('midnight')) {
      _macColorName = 'Midnight';
      _macMatchedTheme = const WriterTheme(
        name: 'Match My Mac (Midnight)',
        backgroundColor: Color(0xFF111622),
        foregroundColor: Color(0xFFE3E3E6),
        sidebarColor: Color(0xFF151E2E),
      );
    } else if (hex.endsWith('09000000') || hex.contains('starlight')) {
      _macColorName = 'Starlight';
      _macMatchedTheme = const WriterTheme(
        name: 'Match My Mac (Starlight)',
        backgroundColor: Color(0xFFF2ECDC),
        foregroundColor: Color(0xFF2F3032),
        sidebarColor: Color(0xFFEADEC6),
      );
    } else {
      // Default fallback
      _macColorName = 'Space Gray';
      _macMatchedTheme = const WriterTheme(
        name: 'Match My Mac (Space Gray)',
        backgroundColor: Color(0xFF2D2F34),
        foregroundColor: Color(0xFFF5F5F7),
        sidebarColor: Color(0xFF27282C),
      );
    }
  }

  Future<void> loadSettings() async {
    await detectMacColor();
    final settings = await _db.getSettings();
    final themeName = settings['theme_name'] as String? ?? 'Paper';
    if (themeName.startsWith('custom_')) {
      final parts = themeName.split('_');
      if (parts.length == 3) {
        final bgVal = int.tryParse(parts[1]) ?? 0xFFFFFFFF;
        final fgVal = int.tryParse(parts[2]) ?? 0xFF000000;
        _currentTheme = WriterTheme(
          name: 'Custom',
          backgroundColor: Color(bgVal),
          foregroundColor: Color(fgVal),
          sidebarColor: Color(bgVal),
        );
      }
    } else if (themeName.startsWith('Match My Mac') || themeName.startsWith('Macbook')) {
      final allMacThemes = [
        if (_macMatchedTheme != null) _macMatchedTheme!,
        ...WriterTheme.macMatchedPresets,
      ];
      _currentTheme = allMacThemes.firstWhere(
        (t) => t.name == themeName,
        orElse: () => WriterTheme.presets[0],
      );
    } else {
      _currentTheme = WriterTheme.presets.firstWhere(
        (t) => t.name == themeName,
        orElse: () => WriterTheme.presets[0],
      );
    }
    notifyListeners();
  }

  void setTheme(WriterTheme theme) {
    _currentTheme = theme;
    if (theme.name.startsWith('Match My Mac') || theme.name.startsWith('Macbook') || theme.name == 'Custom') {
      if (theme.name == 'Custom') {
        final bgStr = '0x${theme.backgroundColor.value.toRadixString(16).padLeft(8, '0')}';
        final fgStr = '0x${theme.foregroundColor.value.toRadixString(16).padLeft(8, '0')}';
        _db.updateSetting('theme_name', 'custom_${bgStr}_${fgStr}');
      } else {
        _db.updateSetting('theme_name', theme.name);
      }
    } else {
      _db.updateSetting('theme_name', theme.name);
    }
    notifyListeners();
  }
}
