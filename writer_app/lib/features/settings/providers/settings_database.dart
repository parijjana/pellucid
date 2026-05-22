// @trace FEAT-20260517-115000-0004
// Description: SQLite database service for persisting application settings and history.

import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class SettingsDatabase {
  static final SettingsDatabase instance = SettingsDatabase._init();
  static Database? _database;

  SettingsDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('settings.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final supportDir = await getApplicationSupportDirectory();
      path = join(supportDir.path, filePath);
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }

    return await openDatabase(
      path,
      version: 7, // Incremented for last_notes_fullscreen_state
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY,
        theme_name TEXT,
        clock_enabled INTEGER,
        current_session_enabled INTEGER,
        target_session_enabled INTEGER,
        focus_timer_enabled INTEGER,
        master_directory_path TEXT,
        current_project_name TEXT,
        last_synced_time TEXT,
        page_width REAL,
        horizontal_position REAL,
        zoom_level REAL,
        battery_guard_enabled INTEGER,
        battery_alert_threshold INTEGER,
        show_battery_percentage INTEGER,
        last_notes_fullscreen_state INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE history (
        date TEXT PRIMARY KEY,
        editor_seconds INTEGER,
        notes_seconds INTEGER,
        word_count_delta INTEGER
      )
    ''');
    
    await db.insert('settings', {
      'id': 1,
      'theme_name': 'Paper',
      'clock_enabled': 0,
      'current_session_enabled': 0,
      'target_session_enabled': 0,
      'focus_timer_enabled': 0,
      'page_width': 800.0,
      'horizontal_position': 0.5,
      'zoom_level': 1.0,
      'battery_guard_enabled': 1,
      'battery_alert_threshold': 20,
      'show_battery_percentage': 1,
      'last_notes_fullscreen_state': 0,
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE settings ADD COLUMN current_project_name TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE history (
          date TEXT PRIMARY KEY,
          editor_seconds INTEGER,
          notes_seconds INTEGER,
          word_count_delta INTEGER
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE settings ADD COLUMN last_synced_time TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE settings ADD COLUMN battery_guard_enabled INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE settings ADD COLUMN battery_alert_threshold INTEGER DEFAULT 20');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE settings ADD COLUMN show_battery_percentage INTEGER DEFAULT 1');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE settings ADD COLUMN last_notes_fullscreen_state INTEGER DEFAULT 0');
    }
  }

  // Settings Methods
  Future<Map<String, dynamic>> getSettings() async {
    final db = await instance.database;
    final maps = await db.query('settings', where: 'id = ?', whereArgs: [1]);
    return maps.first;
  }

  Future<void> updateSetting(String key, dynamic value) async {
    final db = await instance.database;
    dynamic dbValue = value;
    if (value is bool) dbValue = value ? 1 : 0;
    await db.update('settings', {key: dbValue}, where: 'id = ?', whereArgs: [1]);
  }

  // History Methods
  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await instance.database;
    return await db.query('history', orderBy: 'date DESC', limit: 30);
  }

  Future<void> upsertHistory(String date, int editorSec, int notesSec, int words) async {
    final db = await instance.database;
    await db.insert(
      'history',
      {
        'date': date,
        'editor_seconds': editorSec,
        'notes_seconds': notesSec,
        'word_count_delta': words,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
