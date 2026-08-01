// @trace FEAT-20260517-115000-0004
// Description: SQLite database service for persisting application settings and history.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class SettingsDatabase {
  static final SettingsDatabase instance = SettingsDatabase._init();
  static Database? _database;

  static final Map<String, dynamic> _webSettings = {
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
    'google_client_id': null,
    'google_client_secret': null,
    'sync_interval_minutes': 30,
    'master_directory_path': 'scratchpad',
    'master_directory_bookmark': null,
    'current_project_name': 'Scratchpad',
    'typewriter_enabled': 0,
    'paragraph_focus_enabled': 0,
    'codex_linking_enabled': 0,
    'toc_word_counts_enabled': 1,
    'daily_word_goal': 0,
    'spell_check_enabled': 1,
    'last_full_backup_time': null,
  };

  static final List<Map<String, dynamic>> _webHistory = [];
  static final Set<String> _webMigratedManuscriptProjects = {};

  SettingsDatabase._init();

  Future<Database> get database async {
    if (kIsWeb) throw UnsupportedError("SettingsDatabase does not support SQLite on Web. Use mock fallback.");
    if (_database != null) return _database!;
    _database = await _initDB('settings.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) throw UnsupportedError("SettingsDatabase does not support SQLite on Web. Use mock fallback.");
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
      version: 17, // Incremented for the manuscript-filename migration marker table
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
        master_directory_bookmark TEXT,
        current_project_name TEXT,
        last_synced_time TEXT,
        last_full_backup_time TEXT,
        page_width REAL,
        horizontal_position REAL,
        zoom_level REAL,
        battery_guard_enabled INTEGER,
        battery_alert_threshold INTEGER,
        show_battery_percentage INTEGER,
        last_notes_fullscreen_state INTEGER,
        google_client_id TEXT,
        google_client_secret TEXT,
        sync_interval_minutes INTEGER DEFAULT 30,
        typewriter_enabled INTEGER DEFAULT 0,
        paragraph_focus_enabled INTEGER DEFAULT 0,
        codex_linking_enabled INTEGER DEFAULT 0,
        toc_word_counts_enabled INTEGER DEFAULT 1,
        daily_word_goal INTEGER DEFAULT 0,
        spell_check_enabled INTEGER DEFAULT 1
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

    await db.execute('''
      CREATE TABLE manuscript_migration_status (
        project_name TEXT PRIMARY KEY,
        migrated_at TEXT NOT NULL
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
      'sync_interval_minutes': 30,
      'typewriter_enabled': 0,
      'paragraph_focus_enabled': 0,
      'codex_linking_enabled': 0,
      'toc_word_counts_enabled': 1,
      'daily_word_goal': 0,
      'spell_check_enabled': 1,
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
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE settings ADD COLUMN google_client_id TEXT');
      await db.execute('ALTER TABLE settings ADD COLUMN google_client_secret TEXT');
    }
    if (oldVersion < 9) {
      await db.execute('ALTER TABLE settings ADD COLUMN sync_interval_minutes INTEGER DEFAULT 30');
    }
    if (oldVersion < 10) {
      await db.execute('ALTER TABLE settings ADD COLUMN typewriter_enabled INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE settings ADD COLUMN paragraph_focus_enabled INTEGER DEFAULT 0');
    }
    if (oldVersion < 11) {
      await db.execute('ALTER TABLE settings ADD COLUMN codex_linking_enabled INTEGER DEFAULT 0');
    }
    if (oldVersion < 12) {
      await db.execute('ALTER TABLE settings ADD COLUMN toc_word_counts_enabled INTEGER DEFAULT 1');
    }
    if (oldVersion < 13) {
      await db.execute('ALTER TABLE settings ADD COLUMN daily_word_goal INTEGER DEFAULT 0');
    }
    if (oldVersion < 14) {
      await db.execute('ALTER TABLE settings ADD COLUMN spell_check_enabled INTEGER DEFAULT 1');
    }
    if (oldVersion < 15) {
      await db.execute('ALTER TABLE settings ADD COLUMN master_directory_bookmark TEXT');
    }
    if (oldVersion < 16) {
      await db.execute('ALTER TABLE settings ADD COLUMN last_full_backup_time TEXT');
    }
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS manuscript_migration_status (
          project_name TEXT PRIMARY KEY,
          migrated_at TEXT NOT NULL
        )
      ''');
    }
  }

  // ---------------------------------------------------------------------------
  // Manuscript filename migration status (docs/two-way-sync-design.md §1).
  //
  // Tracks which projects have already had their Drive-side manuscript
  // filename reconciled (manuscript.md vs manuscript.md.md), so a fully
  // migrated vault doesn't re-list Drive and re-derive the decision on every
  // app start. This is a fast-path only: the migration decision function
  // itself is idempotent (see manuscript_migration.dart), so re-running for
  // an already-migrated project is harmless even if this marker is somehow
  // lost or stale.
  // ---------------------------------------------------------------------------

  Future<Set<String>> getMigratedManuscriptProjects() async {
    if (kIsWeb) return _webMigratedManuscriptProjects;
    final db = await instance.database;
    final rows = await db.query('manuscript_migration_status', columns: ['project_name']);
    return rows.map((r) => r['project_name'] as String).toSet();
  }

  Future<void> markManuscriptMigrated(String projectName) async {
    if (kIsWeb) {
      _webMigratedManuscriptProjects.add(projectName);
      return;
    }
    final db = await instance.database;
    await db.insert(
      'manuscript_migration_status',
      {
        'project_name': projectName,
        'migrated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Settings Methods
  Future<Map<String, dynamic>> getSettings() async {
    if (kIsWeb) {
      return _webSettings;
    }
    final db = await instance.database;
    final maps = await db.query('settings', where: 'id = ?', whereArgs: [1]);
    if (maps.isEmpty) {
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
        'google_client_id': null,
        'google_client_secret': null,
        'sync_interval_minutes': 30,
        'typewriter_enabled': 0,
        'paragraph_focus_enabled': 0,
        'codex_linking_enabled': 0,
        'toc_word_counts_enabled': 1,
        'daily_word_goal': 0,
      });
      final mapsRetry = await db.query('settings', where: 'id = ?', whereArgs: [1]);
      return mapsRetry.first;
    }
    return maps.first;
  }

  Future<void> updateSetting(String key, dynamic value) async {
    if (kIsWeb) {
      dynamic dbValue = value;
      if (value is bool) dbValue = value ? 1 : 0;
      _webSettings[key] = dbValue;
      return;
    }
    final db = await instance.database;
    dynamic dbValue = value;
    if (value is bool) dbValue = value ? 1 : 0;
    
    final maps = await db.query('settings', where: 'id = ?', whereArgs: [1]);
    if (maps.isEmpty) {
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
        'google_client_id': null,
        'google_client_secret': null,
        'sync_interval_minutes': 30,
        'typewriter_enabled': 0,
        'paragraph_focus_enabled': 0,
        'codex_linking_enabled': 0,
        'toc_word_counts_enabled': 1,
        'daily_word_goal': 0,
      });
    }
    await db.update('settings', {key: dbValue}, where: 'id = ?', whereArgs: [1]);
  }

  // History Methods
  Future<List<Map<String, dynamic>>> getHistory() async {
    if (kIsWeb) {
      return _webHistory;
    }
    final db = await instance.database;
    return await db.query('history', orderBy: 'date DESC', limit: 30);
  }

  Future<void> upsertHistory(String date, int editorSec, int notesSec, int words) async {
    if (kIsWeb) {
      _webHistory.removeWhere((item) => item['date'] == date);
      _webHistory.add({
        'date': date,
        'editor_seconds': editorSec,
        'notes_seconds': notesSec,
        'word_count_delta': words,
      });
      return;
    }
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
