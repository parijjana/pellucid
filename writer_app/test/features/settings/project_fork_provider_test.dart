// Description: Forking a mirrored project, against a real in-memory
// filesystem. The load-bearing assertion is the "reused" branch: an existing
// fork holds an earlier session's edits and must never be refreshed from the
// mirror.

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sidebar/providers/note_card.dart';
import 'package:pellucid/features/sync/services/project_fork.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  late MemoryFileSystem fs;
  late StorageService storage;
  late MockSettingsDatabase db;
  late SettingsProvider settings;

  setUp(() async {
    fs = MemoryFileSystem();
    storage = StorageService(fileSystem: fs);
    db = MockSettingsDatabase();
    when(() => db.getMirroredProjects()).thenAnswer((_) async => <String>{});
    when(() => db.updateSetting(any(), any())).thenAnswer((_) async {});
    when(() => db.getSettings()).thenAnswer((_) async => <String, dynamic>{});
    when(() => db.markProjectMirrored(any())).thenAnswer((_) async {});
    when(() => db.unmarkProjectMirrored(any())).thenAnswer((_) async {});

    settings = SettingsProvider(settingsDatabase: db, storageService: storage);
    await settings.setMasterDirectory('/master');
  });

  String documentOf(String project) =>
      fs.file('/master/$project/document.md').readAsStringSync();

  test('creates a fork seeded with the editor text and switches to it', () async {
    await storage.initProject('/master', 'Novel', initialContent: 'Chapter One');

    final result = await settings.forkMirroredProject(
      sourceName: 'Novel',
      device: ForkDevice.iPad,
      seedContent: 'Chapter One, and a new sentence',
    );

    expect(result.outcome, ForkOutcome.created);
    expect(result.forkName, 'Novel_iPad');
    expect(documentOf('Novel_iPad'), 'Chapter One, and a new sentence');
    expect(settings.currentProjectName, 'Novel_iPad');
  });

  test('leaves the mirror exactly as it was', () async {
    await storage.initProject('/master', 'Novel', initialContent: 'Chapter One');

    await settings.forkMirroredProject(
      sourceName: 'Novel',
      device: ForkDevice.iPad,
      seedContent: 'a stray keystroke',
    );

    expect(documentOf('Novel'), 'Chapter One');
  });

  test('carries the mirror\'s notes and stats into a new fork', () async {
    await storage.initProject('/master', 'Novel', initialContent: 'Chapter One');
    await storage.saveNotes('/master/Novel', [
      NoteCard(title: 'A note', content: 'body', category: 'general'),
    ]);

    await settings.forkMirroredProject(
      sourceName: 'Novel',
      device: ForkDevice.iPad,
      seedContent: 'Chapter One',
    );

    final notes = await storage.readNotes('/master/Novel_iPad');
    expect(notes.value.single.title, 'A note');
  });

  test('REUSES an existing fork and never overwrites its earlier edits',
      () async {
    // Session one forked and wrote a draft; session two opens the mirror,
    // which has since re-pulled from the Mac, and types again. Refreshing the
    // fork from the mirror here would destroy the session-one draft.
    await storage.initProject('/master', 'Novel', initialContent: 'Chapter One');
    await storage.initProject('/master', 'Novel_iPad',
        initialContent: 'a whole session of work');

    final result = await settings.forkMirroredProject(
      sourceName: 'Novel',
      device: ForkDevice.iPad,
      seedContent: 'Chapter One, and a stray keystroke',
    );

    expect(result.outcome, ForkOutcome.reused);
    expect(documentOf('Novel_iPad'), 'a whole session of work');
    expect(settings.currentProjectName, 'Novel_iPad');
  });

  test('refuses to seed a blank fork when the mirror could not be read',
      () async {
    // With no seed content, the fork copies the mirror. If that read failed
    // the mirror's real content is unknown, and a blank fork would look like
    // a project whose words had been deleted.
    final unreadable = _UnreadableStorageService(fs);
    settings = SettingsProvider(settingsDatabase: db, storageService: unreadable);
    await settings.setMasterDirectory('/master');

    final result = await settings.forkMirroredProject(
      sourceName: 'Novel',
      device: ForkDevice.iPad,
    );

    expect(result.outcome, ForkOutcome.failed);
    expect(fs.directory('/master/Novel_iPad').existsSync(), isFalse);
  });

  test('a different device class gets a different fork', () async {
    await storage.initProject('/master', 'Novel', initialContent: 'Chapter One');

    final iPad = await settings.forkMirroredProject(
        sourceName: 'Novel', device: ForkDevice.iPad, seedContent: 'a');
    final iPhone = await settings.forkMirroredProject(
        sourceName: 'Novel', device: ForkDevice.iPhone, seedContent: 'b');

    expect(iPad.forkName, isNot(iPhone.forkName));
    expect(documentOf('Novel_iPad'), 'a');
    expect(documentOf('Novel_iPhone'), 'b');
  });

  test('renaming a mirror moves its marker to the new name', () async {
    // A marker left on the old name would silently make any future project
    // given that name unwritable.
    when(() => db.getMirroredProjects()).thenAnswer((_) async => {'Novel'});
    settings = SettingsProvider(settingsDatabase: db, storageService: storage);
    await settings.loadSettings();
    await settings.setMasterDirectory('/master');
    await storage.initProject('/master', 'Novel', initialContent: 'x');

    await settings.renameProject('Novel', 'Novella');

    verify(() => db.unmarkProjectMirrored('Novel')).called(1);
    verify(() => db.markProjectMirrored('Novella')).called(1);
  });
}

/// A real StorageService whose document read fails the way an undownloaded
/// cloud placeholder does.
class _UnreadableStorageService extends StorageService {
  _UnreadableStorageService(FileSystem fileSystem)
      : super(fileSystem: fileSystem);

  @override
  Future<ReadResult<String>> readDocument(String projectPath) async =>
      ReadResult.failed('', Exception('operation not permitted'));
}
