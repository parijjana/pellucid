// Description: Settings DB migrations 18 → 19 (editor_font, slice 6) → 20
// (language/editing switches, slice 8). Both slices first claimed v19; the
// integration merge split them, so check every starting point lands on the
// same columns as a fresh install.

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _added = {
  'editor_font': "'serif'",
  'grammar_hints_enabled': '1',
  'smart_punctuation_enabled': '1',
  'auto_continue_lists_enabled': '1',
  'attribution_duplicate_highlight_enabled': '1',
};

Future<Map<String, String?>> _columns(Database db) async {
  final rows = await db.rawQuery('PRAGMA table_info(settings)');
  return {for (final r in rows) r['name'] as String: r['dflt_value'] as String?};
}

Future<Database> _open() => databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false));

void main() {
  sqfliteFfiInit();

  test('schema version is 20', () {
    expect(SettingsDatabase.schemaVersion, 20);
  });

  test('fresh install has every new column with its default', () async {
    final db = await _open();
    await SettingsDatabase.instance.createForTest(db);
    final cols = await _columns(db);
    _added.forEach((name, dflt) => expect(cols[name], dflt, reason: name));
    await db.close();
  });

  for (final from in [18, 19]) {
    test('upgrade from v$from adds the missing columns, keeps the row', () async {
      final db = await _open();
      final v19 = from == 19 ? ", editor_font TEXT DEFAULT 'serif'" : '';
      await db.execute(
          'CREATE TABLE settings (id INTEGER PRIMARY KEY, spell_check_enabled INTEGER DEFAULT 1$v19)');
      await db.insert('settings', {'id': 1, 'spell_check_enabled': 0});
      await SettingsDatabase.instance.upgradeForTest(db, from);

      final cols = await _columns(db);
      _added.forEach((name, dflt) => expect(cols[name], dflt, reason: name));
      final row = (await db.query('settings')).single;
      expect(row['spell_check_enabled'], 0);
      expect(row['editor_font'], 'serif');
      expect(row['grammar_hints_enabled'], 1);
      expect(row['attribution_duplicate_highlight_enabled'], 1);
      await db.close();
    });
  }
}
