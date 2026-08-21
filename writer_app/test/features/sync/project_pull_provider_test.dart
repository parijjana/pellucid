// Description: SyncProvider's Drive -> local pull. The Drive side is mocked;
// the local side is a real in-memory filesystem, so these assert what
// actually lands on disk rather than which methods were called.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/sync/models/logical_file.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/google_drive_sync_service.dart';
import 'package:pellucid/features/sync/services/manuscript_migration.dart';
import 'package:pellucid/features/sync/services/project_pull.dart';

class MockGoogleDriveSyncService extends Mock implements GoogleDriveSyncService {}

class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(LogicalFile.manuscript);
  });

  late MockGoogleDriveSyncService mockService;
  late MockSettingsDatabase mockDb;
  late MemoryFileSystem fs;
  late StorageService storage;
  late SyncProvider sync;

  const masterPath = '/master';

  setUp(() async {
    mockService = MockGoogleDriveSyncService();
    mockDb = MockSettingsDatabase();
    fs = MemoryFileSystem();
    storage = StorageService(fileSystem: fs);

    await fs.directory(masterPath).create(recursive: true);

    when(() => mockDb.getSettings()).thenAnswer((_) async => {'last_synced_time': null});
    when(() => mockDb.updateSetting(any(), any())).thenAnswer((_) async {});
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);

    // Default: no optional files in Drive.
    when(() => mockService.downloadProjectFile(any(), any()))
        .thenAnswer((_) async => null);

    sync = SyncProvider(service: mockService, settingsDatabase: mockDb);
    // The constructor's login check is async; let it settle.
    await Future<void>.delayed(Duration.zero);
  });

  /// Puts a manuscript in Drive under [name] with the given content.
  void driveHasManuscript({
    String project = 'Novel',
    String name = 'manuscript.md',
    String content = 'Chapter One',
    DateTime? modifiedTime,
  }) {
    final file = drive.File()
      ..id = '$project-$name'
      ..name = name
      ..modifiedTime = modifiedTime;
    when(() => mockService.findRawFileInProject(project, name))
        .thenAnswer((_) async => file);
    when(() => mockService.downloadFileContent(file.id!))
        .thenAnswer((_) async => content);
  }

  void driveLacks(String project, String name) {
    when(() => mockService.findRawFileInProject(project, name))
        .thenAnswer((_) async => null);
  }

  String localDocument(String project) =>
      fs.file('$masterPath/$project/document.md').readAsStringSync();

  group('listRemoteProjects', () {
    test('pairs the vault against the local library', () async {
      when(() => mockService.listProjectNames())
          .thenAnswer((_) async => ['Novel', 'Sketches']);
      await storage.initProject(masterPath, 'Novel');

      final remote = await sync.listRemoteProjects(
        masterPath: masterPath,
        storageService: storage,
      );

      expect(remote.map((p) => p.name), ['Novel', 'Sketches']);
      expect(remote.firstWhere((p) => p.name == 'Novel').isPullable, isFalse);
      expect(remote.firstWhere((p) => p.name == 'Sketches').isPullable, isTrue);
    });

    test('is empty when signed out, and never calls Drive', () async {
      when(() => mockService.isLoggedIn).thenAnswer((_) async => false);
      sync = SyncProvider(service: mockService, settingsDatabase: mockDb);

      final remote = await sync.listRemoteProjects(
        masterPath: masterPath,
        storageService: storage,
      );

      expect(remote, isEmpty);
      verifyNever(() => mockService.listProjectNames());
    });
  });

  group('pullProject', () {
    test('writes the manuscript into a new local project', () async {
      driveHasManuscript(content: 'Chapter One');
      driveLacks('Novel', legacyManuscriptDriveFileName);

      final result = await sync.pullProject(
        projectName: 'Novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.outcome, PullOutcome.pulled);
      expect(result.filesPulled, contains(LogicalFile.manuscript));
      expect(localDocument('Novel'), 'Chapter One');
    });

    test('reads the legacy filename when the vault is unmigrated', () async {
      driveLacks('Novel', canonicalManuscriptDriveFileName);
      driveHasManuscript(
          name: legacyManuscriptDriveFileName, content: 'The live draft');

      final result = await sync.pullProject(
        projectName: 'Novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.outcome, PullOutcome.pulled);
      expect(localDocument('Novel'), 'The live draft');
    });

    test('takes the newer of the two manuscript filenames', () async {
      driveHasManuscript(
        content: 'stale canonical',
        modifiedTime: DateTime.utc(2026, 8, 1),
      );
      driveHasManuscript(
        name: legacyManuscriptDriveFileName,
        content: 'the newer legacy copy',
        modifiedTime: DateTime.utc(2026, 8, 2),
      );

      await sync.pullProject(
        projectName: 'Novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(localDocument('Novel'), 'the newer legacy copy');
    });

    test('refuses rather than guessing when the two cannot be ordered', () async {
      driveHasManuscript(content: 'a');
      driveHasManuscript(name: legacyManuscriptDriveFileName, content: 'b');

      final result = await sync.pullProject(
        projectName: 'Novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.outcome, PullOutcome.ambiguousManuscript);
      expect(fs.directory('$masterPath/Novel').existsSync(), isFalse);
    });

    test('NEVER overwrites a project this device already has', () async {
      // The whole safety argument for a one-way pull. Reconciling a name that
      // exists on both sides is 1.2's job, not this path's.
      await storage.initProject(masterPath, 'Novel',
          initialContent: 'local words that must survive');
      driveHasManuscript(content: 'the remote copy');
      driveLacks('Novel', legacyManuscriptDriveFileName);

      final result = await sync.pullProject(
        projectName: 'Novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.outcome, PullOutcome.alreadyExistsLocally);
      expect(localDocument('Novel'), 'local words that must survive');
    });

    test('refuses a case-variant name too — the filesystem cannot tell them apart',
        () async {
      await storage.initProject(masterPath, 'Novel',
          initialContent: 'local words that must survive');
      driveHasManuscript(project: 'novel', content: 'the remote copy');
      driveLacks('novel', legacyManuscriptDriveFileName);

      final result = await sync.pullProject(
        projectName: 'novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.outcome, PullOutcome.alreadyExistsLocally);
      expect(localDocument('Novel'), 'local words that must survive');
    });

    test('a project with no manuscript leaves nothing on disk', () async {
      driveLacks('Empty', canonicalManuscriptDriveFileName);
      driveLacks('Empty', legacyManuscriptDriveFileName);

      final result = await sync.pullProject(
        projectName: 'Empty',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.outcome, PullOutcome.noManuscript);
      expect(fs.directory('$masterPath/Empty').existsSync(), isFalse);
    });

    test('pulls notes and stats when Drive has them', () async {
      driveHasManuscript();
      driveLacks('Novel', legacyManuscriptDriveFileName);
      when(() => mockService.downloadProjectFile('Novel', LogicalFile.notes))
          .thenAnswer((_) async => jsonEncode([
                {'title': 'A note', 'content': 'body', 'category': 'general'}
              ]));
      when(() => mockService.downloadProjectFile('Novel', LogicalFile.stats))
          .thenAnswer((_) async => jsonEncode({'totalWordCount': 1234}));

      final result = await sync.pullProject(
        projectName: 'Novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.filesPulled,
          containsAll([LogicalFile.notes, LogicalFile.stats]));
      final notes = await storage.readNotes('$masterPath/Novel');
      expect(notes.value.single.title, 'A note');
      final stats = await storage.readProjectStats('$masterPath/Novel');
      expect(stats.totalWordCount, 1234);
    });

    test('skips an unparseable notes.json instead of writing garbage', () async {
      // Writing it locally would only trip the read-failure latch later and
      // lock the project's notes for no reason.
      driveHasManuscript();
      driveLacks('Novel', legacyManuscriptDriveFileName);
      when(() => mockService.downloadProjectFile('Novel', LogicalFile.notes))
          .thenAnswer((_) async => '{not json at all');

      final result = await sync.pullProject(
        projectName: 'Novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.outcome, PullOutcome.pulled);
      expect(result.filesSkipped, contains(LogicalFile.notes));
      final notes = await storage.readNotes('$masterPath/Novel');
      expect(notes.value, isEmpty);
      expect(notes.failed, isFalse);
    });

    test('refuses when signed out, and never touches disk', () async {
      when(() => mockService.isLoggedIn).thenAnswer((_) async => false);
      sync = SyncProvider(service: mockService, settingsDatabase: mockDb);

      final result = await sync.pullProject(
        projectName: 'Novel',
        masterPath: masterPath,
        storageService: storage,
      );

      expect(result.outcome, PullOutcome.notLoggedIn);
      expect(fs.directory('$masterPath/Novel').existsSync(), isFalse);
    });
  });
}
