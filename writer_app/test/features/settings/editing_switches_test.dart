// Description: Backlog item 26 switches: all on by default, stored like the
// other settings, loaded back on start.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';

class _MockDb extends Mock implements SettingsDatabase {}

class _MockStorage extends Mock implements StorageService {}

void main() {
  late _MockDb db;
  late SettingsProvider settings;

  setUp(() {
    db = _MockDb();
    when(() => db.getMirroredProjects()).thenAnswer((_) async => <String>{});
    when(() => db.updateSetting(any(), any())).thenAnswer((_) async {});
    settings = SettingsProvider(settingsDatabase: db, storageService: _MockStorage());
  });

  test('all four switches default to on', () {
    expect(settings.grammarHintsEnabled, isTrue);
    expect(settings.smartPunctuationEnabled, isTrue);
    expect(settings.autoContinueListsEnabled, isTrue);
    expect(settings.attributionDuplicateHighlightEnabled, isTrue);
  });

  test('each toggle updates the getter, notifies and stores its column', () {
    var notified = 0;
    settings.addListener(() => notified++);
    settings.toggleGrammarHints(false);
    settings.toggleSmartPunctuation(false);
    settings.toggleAutoContinueLists(false);
    settings.toggleAttributionDuplicateHighlight(false);
    expect(settings.grammarHintsEnabled, isFalse);
    expect(settings.smartPunctuationEnabled, isFalse);
    expect(settings.autoContinueListsEnabled, isFalse);
    expect(settings.attributionDuplicateHighlightEnabled, isFalse);
    expect(notified, 4);
    for (final k in [
      'grammar_hints_enabled',
      'smart_punctuation_enabled',
      'auto_continue_lists_enabled',
      'attribution_duplicate_highlight_enabled',
    ]) {
      verify(() => db.updateSetting(k, false)).called(1);
    }
  });
}
