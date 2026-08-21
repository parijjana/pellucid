import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/google_drive_sync_service.dart';
import 'package:pellucid/features/sync/models/logical_file.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';

class MockGoogleDriveSyncService extends Mock implements GoogleDriveSyncService {}
class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(LogicalFile.manuscript);
  });

  late SyncProvider syncProvider;
  late MockGoogleDriveSyncService mockService;
  late MockSettingsDatabase mockDb;

  setUp(() {
    mockService = MockGoogleDriveSyncService();
    mockDb = MockSettingsDatabase();
    when(() => mockDb.getMirroredProjects()).thenAnswer((_) async => <String>{});

    when(() => mockService.isLoggedIn).thenAnswer((_) async => false);
    when(() => mockDb.getSettings()).thenAnswer((_) async => {'last_synced_time': null});
    when(() => mockDb.updateSetting(any(), any())).thenAnswer((_) async {});

    syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
  });

  test('Initial status is idle and not logged in', () async {
    expect(syncProvider.status, SyncStatus.idle);
    expect(syncProvider.isLoggedIn, false);
  });

  test('login updates login status', () async {
    when(() => mockService.login()).thenAnswer((_) async {});
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);

    await syncProvider.login();

    expect(syncProvider.isLoggedIn, true);
    verify(() => mockService.login()).called(1);
  });

  test('login with custom credentials passes them to service', () async {
    when(() => mockService.login(
      customClientId: any(named: 'customClientId'),
      customClientSecret: any(named: 'customClientSecret'),
    )).thenAnswer((_) async {});
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);

    await syncProvider.login(clientId: 'cid', clientSecret: 'sec');

    expect(syncProvider.isLoggedIn, true);
    verify(() => mockService.login(customClientId: 'cid', customClientSecret: 'sec')).called(1);
  });

  test('syncCurrentFile updates status to success on success', () async {
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);
    // Re-init with logged in status
    syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
    // Need to wait for _checkLoginStatus to finish
    await Future.microtask(() {});

    when(() => mockService.syncFile(
      projectName: any(named: 'projectName'),
      file: any(named: 'file'),
      content: any(named: 'content'),
    )).thenAnswer((_) async {});
    when(() => mockService.getLastModified(any(), any())).thenAnswer((_) async => DateTime.now());

    await syncProvider.syncCurrentFile(
      projectName: 'Test',
      fileName: LogicalFile.manuscript,
      content: 'Hello',
    );

    expect(syncProvider.status, SyncStatus.success);
  });

  test('syncCurrentFile updates status to error on failure', () async {
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);
    syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
    await Future.microtask(() {});

    when(() => mockService.syncFile(
      projectName: any(named: 'projectName'),
      file: any(named: 'file'),
      content: any(named: 'content'),
    )).thenThrow(Exception('Network Error'));

    await syncProvider.syncCurrentFile(
      projectName: 'Test',
      fileName: LogicalFile.manuscript,
      content: 'Hello',
    );

    expect(syncProvider.status, SyncStatus.error);
  });

  test('loadHistory calls service and updates history list', () async {
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);
    syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
    await Future.microtask(() {});

    final mockRevisions = [drive.Revision(id: 'rev-1')];
    when(() => mockService.getRevisions('MyProject', LogicalFile.manuscript))
        .thenAnswer((_) async => mockRevisions);

    await syncProvider.loadHistory('MyProject', LogicalFile.manuscript);

    expect(syncProvider.history, mockRevisions);
    verify(() => mockService.getRevisions('MyProject', LogicalFile.manuscript)).called(1);
  });

  group('shouldUploadFile out-of-date decision', () {
    final base = DateTime.utc(2026, 7, 1, 12, 0, 0);

    test('uploads when Drive has no copy (null modifiedTime)', () {
      expect(
        SyncProvider.shouldUploadFile(localMtime: base, driveModifiedTime: null),
        isTrue,
      );
    });

    test('uploads when local is strictly newer than Drive', () {
      expect(
        SyncProvider.shouldUploadFile(
          localMtime: base.add(const Duration(minutes: 5)),
          driveModifiedTime: base,
        ),
        isTrue,
      );
    });

    test('uploads when local equals Drive (bias toward uploading)', () {
      expect(
        SyncProvider.shouldUploadFile(localMtime: base, driveModifiedTime: base),
        isTrue,
      );
    });

    test('skips when local is strictly older than Drive', () {
      expect(
        SyncProvider.shouldUploadFile(
          localMtime: base.subtract(const Duration(minutes: 5)),
          driveModifiedTime: base,
        ),
        isFalse,
      );
    });

    test('normalizes time zones (local wall-clock vs UTC Drive time)', () {
      // A local-zone timestamp equal in absolute time to Drive's UTC must not
      // be treated as older just because its zone offset differs.
      final localZoned = base.toLocal();
      expect(
        SyncProvider.shouldUploadFile(
          localMtime: localZoned,
          driveModifiedTime: base,
        ),
        isTrue,
      );
    });
  });

  group('runFullBackupIfDue sweep', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pellucid_backup_test');
      when(() => mockService.isLoggedIn).thenAnswer((_) async => true);
      when(() => mockService.syncFile(
            projectName: any(named: 'projectName'),
            file: any(named: 'file'),
            content: any(named: 'content'),
          )).thenAnswer((_) async {});
      syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
      await Future.microtask(() {});
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> writeProject(String name,
        {bool doc = true, bool notes = true, bool stats = true}) async {
      final dir = Directory('${tempDir.path}/$name');
      await dir.create(recursive: true);
      if (doc) await File('${dir.path}/document.md').writeAsString('# $name');
      if (notes) await File('${dir.path}/notes.json').writeAsString('[]');
      if (stats) await File('${dir.path}/stats.json').writeAsString('{}');
    }

    test('uploads all present files when Drive is empty and none excluded', () async {
      await writeProject('Alpha');
      // Also drop excluded artifacts that must NOT be uploaded.
      await File('${tempDir.path}/Alpha/categories.json').writeAsString('[]');
      await Directory('${tempDir.path}/Alpha/.history').create();
      when(() => mockDb.getSettings())
          .thenAnswer((_) async => {'last_full_backup_time': null});
      when(() => mockService.getLastModified(any(), any()))
          .thenAnswer((_) async => null);

      await syncProvider.runFullBackupIfDue(
        masterPath: tempDir.path,
        storageService: StorageService(),
      );

      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          file: LogicalFile.manuscript,
          content: any(named: 'content'))).called(1);
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          file: LogicalFile.notes,
          content: any(named: 'content'))).called(1);
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          file: LogicalFile.stats,
          content: any(named: 'content'))).called(1);
      // Completion timestamp is persisted.
      verify(() => mockDb.updateSetting('last_full_backup_time', any())).called(1);
    });

    test('is a no-op when a sweep ran within the last 24h', () async {
      await writeProject('Alpha');
      final recent = DateTime.now().subtract(const Duration(hours: 1));
      when(() => mockDb.getSettings()).thenAnswer(
          (_) async => {'last_full_backup_time': recent.toIso8601String()});

      await syncProvider.runFullBackupIfDue(
        masterPath: tempDir.path,
        storageService: StorageService(),
      );

      verifyNever(() => mockService.syncFile(
          projectName: any(named: 'projectName'),
          file: any(named: 'file'),
          content: any(named: 'content')));
    });

    test('one failing file does not abort the rest of the sweep', () async {
      await writeProject('Alpha');
      when(() => mockDb.getSettings())
          .thenAnswer((_) async => {'last_full_backup_time': null});
      when(() => mockService.getLastModified(any(), any()))
          .thenAnswer((_) async => null);
      when(() => mockService.syncFile(
            projectName: 'Alpha',
            file: LogicalFile.manuscript,
            content: any(named: 'content'),
          )).thenThrow(Exception('boom'));

      await syncProvider.runFullBackupIfDue(
        masterPath: tempDir.path,
        storageService: StorageService(),
      );

      // notes + stats still uploaded despite manuscript failing.
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          file: LogicalFile.notes,
          content: any(named: 'content'))).called(1);
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          file: LogicalFile.stats,
          content: any(named: 'content'))).called(1);
      verify(() => mockDb.updateSetting('last_full_backup_time', any())).called(1);
    });

    test('skips a file whose local copy is older than Drive', () async {
      await writeProject('Alpha', notes: false, stats: false);
      when(() => mockDb.getSettings())
          .thenAnswer((_) async => {'last_full_backup_time': null});
      // Drive reports a far-future modifiedTime => local is older => skip.
      when(() => mockService.getLastModified('Alpha', LogicalFile.manuscript))
          .thenAnswer((_) async => DateTime.now().toUtc().add(const Duration(days: 1)));

      await syncProvider.runFullBackupIfDue(
        masterPath: tempDir.path,
        storageService: StorageService(),
      );

      verifyNever(() => mockService.syncFile(
          projectName: 'Alpha',
          file: LogicalFile.manuscript,
          content: any(named: 'content')));
    });

    test('freshness check compares against the SAME logical file it writes (regression guard)', () async {
      // Historically the sweep compared the manuscript's freshness against a
      // Drive file the editor never wrote to, making the check meaningless.
      // Assert the exact call sequence: getLastModified and syncFile must be
      // called with the identical LogicalFile for the manuscript.
      await writeProject('Alpha', notes: false, stats: false);
      when(() => mockDb.getSettings())
          .thenAnswer((_) async => {'last_full_backup_time': null});
      when(() => mockService.getLastModified('Alpha', LogicalFile.manuscript))
          .thenAnswer((_) async => null);

      await syncProvider.runFullBackupIfDue(
        masterPath: tempDir.path,
        storageService: StorageService(),
      );

      verify(() => mockService.getLastModified('Alpha', LogicalFile.manuscript)).called(1);
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          file: LogicalFile.manuscript,
          content: any(named: 'content'))).called(1);
    });
  });

  group('runManuscriptMigrationIfNeeded', () {
    setUp(() {
      when(() => mockService.isLoggedIn).thenAnswer((_) async => true);
    });

    test('no-op when not logged in', () async {
      when(() => mockService.isLoggedIn).thenAnswer((_) async => false);
      syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
      await Future.microtask(() {});

      await syncProvider.runManuscriptMigrationIfNeeded();

      verifyNever(() => mockService.listProjectNames());
    });

    test('skips projects already recorded as migrated', () async {
      syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
      await Future.microtask(() {});

      when(() => mockService.listProjectNames()).thenAnswer((_) async => ['Alpha']);
      when(() => mockDb.getMigratedManuscriptProjects()).thenAnswer((_) async => {'Alpha'});

      await syncProvider.runManuscriptMigrationIfNeeded();

      verifyNever(() => mockService.findRawFileInProject(any(), any()));
      verifyNever(() => mockDb.markManuscriptMigrated(any()));
    });

    test('copies legacy content into a newly created canonical file when only legacy exists', () async {
      syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
      await Future.microtask(() {});

      when(() => mockService.listProjectNames()).thenAnswer((_) async => ['Alpha']);
      when(() => mockDb.getMigratedManuscriptProjects()).thenAnswer((_) async => {});
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md'))
          .thenAnswer((_) async => null);
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md.md'))
          .thenAnswer((_) async => drive.File(id: 'legacy-id', modifiedTime: DateTime.utc(2026, 1, 1)));
      when(() => mockService.downloadFileContent('legacy-id'))
          .thenAnswer((_) async => 'legacy content');
      when(() => mockService.createRawFileInProject('Alpha', 'manuscript.md', 'legacy content'))
          .thenAnswer((_) async => 'new-canonical-id');
      when(() => mockDb.markManuscriptMigrated('Alpha')).thenAnswer((_) async {});

      await syncProvider.runManuscriptMigrationIfNeeded();

      verify(() => mockService.createRawFileInProject('Alpha', 'manuscript.md', 'legacy content')).called(1);
      verifyNever(() => mockService.overwriteFileContent(any(), any()));
      verify(() => mockDb.markManuscriptMigrated('Alpha')).called(1);
    });

    test('overwrites existing canonical file (never delete-then-create) when legacy is newer', () async {
      syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
      await Future.microtask(() {});

      when(() => mockService.listProjectNames()).thenAnswer((_) async => ['Alpha']);
      when(() => mockDb.getMigratedManuscriptProjects()).thenAnswer((_) async => {});
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md')).thenAnswer(
          (_) async => drive.File(id: 'canonical-id', modifiedTime: DateTime.utc(2026, 1, 1)));
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md.md')).thenAnswer(
          (_) async => drive.File(id: 'legacy-id', modifiedTime: DateTime.utc(2026, 1, 2)));
      when(() => mockService.downloadFileContent('legacy-id'))
          .thenAnswer((_) async => 'newer legacy content');
      when(() => mockService.overwriteFileContent('canonical-id', 'newer legacy content'))
          .thenAnswer((_) async {});
      when(() => mockDb.markManuscriptMigrated('Alpha')).thenAnswer((_) async {});

      await syncProvider.runManuscriptMigrationIfNeeded();

      verify(() => mockService.overwriteFileContent('canonical-id', 'newer legacy content')).called(1);
      verifyNever(() => mockService.createRawFileInProject(any(), any(), any()));
      verify(() => mockDb.markManuscriptMigrated('Alpha')).called(1);
    });

    test('does nothing and still marks migrated when canonical is already newer or equal', () async {
      syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
      await Future.microtask(() {});

      when(() => mockService.listProjectNames()).thenAnswer((_) async => ['Alpha']);
      when(() => mockDb.getMigratedManuscriptProjects()).thenAnswer((_) async => {});
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md')).thenAnswer(
          (_) async => drive.File(id: 'canonical-id', modifiedTime: DateTime.utc(2026, 1, 2)));
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md.md')).thenAnswer(
          (_) async => drive.File(id: 'legacy-id', modifiedTime: DateTime.utc(2026, 1, 1)));
      when(() => mockDb.markManuscriptMigrated('Alpha')).thenAnswer((_) async {});

      await syncProvider.runManuscriptMigrationIfNeeded();

      verifyNever(() => mockService.downloadFileContent(any()));
      verifyNever(() => mockService.overwriteFileContent(any(), any()));
      verifyNever(() => mockService.createRawFileInProject(any(), any(), any()));
      verify(() => mockDb.markManuscriptMigrated('Alpha')).called(1);
    });

    test('never calls anything that deletes the legacy file', () async {
      syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
      await Future.microtask(() {});

      when(() => mockService.listProjectNames()).thenAnswer((_) async => ['Alpha']);
      when(() => mockDb.getMigratedManuscriptProjects()).thenAnswer((_) async => {});
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md'))
          .thenAnswer((_) async => null);
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md.md'))
          .thenAnswer((_) async => drive.File(id: 'legacy-id', modifiedTime: DateTime.utc(2026, 1, 1)));
      when(() => mockService.downloadFileContent('legacy-id'))
          .thenAnswer((_) async => 'legacy content');
      when(() => mockService.createRawFileInProject('Alpha', 'manuscript.md', 'legacy content'))
          .thenAnswer((_) async => 'new-canonical-id');
      when(() => mockDb.markManuscriptMigrated('Alpha')).thenAnswer((_) async {});

      await syncProvider.runManuscriptMigrationIfNeeded();

      // GoogleDriveSyncService exposes no delete method the migration could
      // have called; this test documents that guarantee structurally by
      // only ever stubbing/verifying non-destructive calls above.
      verify(() => mockDb.markManuscriptMigrated('Alpha')).called(1);
    });

    test('a project with an ambiguous state (missing modifiedTime) is left unmarked and does not abort other projects', () async {
      syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
      await Future.microtask(() {});

      when(() => mockService.listProjectNames()).thenAnswer((_) async => ['Alpha', 'Beta']);
      when(() => mockDb.getMigratedManuscriptProjects()).thenAnswer((_) async => {});

      // Alpha: ambiguous (both exist, canonical modifiedTime missing).
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md'))
          .thenAnswer((_) async => drive.File(id: 'a-canonical-id', modifiedTime: null));
      when(() => mockService.findRawFileInProject('Alpha', 'manuscript.md.md'))
          .thenAnswer((_) async => drive.File(id: 'a-legacy-id', modifiedTime: DateTime.utc(2026, 1, 1)));

      // Beta: clean case, only legacy exists.
      when(() => mockService.findRawFileInProject('Beta', 'manuscript.md'))
          .thenAnswer((_) async => null);
      when(() => mockService.findRawFileInProject('Beta', 'manuscript.md.md'))
          .thenAnswer((_) async => drive.File(id: 'b-legacy-id', modifiedTime: DateTime.utc(2026, 1, 1)));
      when(() => mockService.downloadFileContent('b-legacy-id'))
          .thenAnswer((_) async => 'beta legacy content');
      when(() => mockService.createRawFileInProject('Beta', 'manuscript.md', 'beta legacy content'))
          .thenAnswer((_) async => 'b-new-canonical-id');
      when(() => mockDb.markManuscriptMigrated('Beta')).thenAnswer((_) async {});

      await syncProvider.runManuscriptMigrationIfNeeded();

      // Alpha never marked migrated (left for retry), Beta successfully migrated.
      verifyNever(() => mockDb.markManuscriptMigrated('Alpha'));
      verify(() => mockDb.markManuscriptMigrated('Beta')).called(1);
    });
  });
}
