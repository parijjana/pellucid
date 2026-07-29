import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/google_drive_sync_service.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';

class MockGoogleDriveSyncService extends Mock implements GoogleDriveSyncService {}
class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SyncProvider syncProvider;
  late MockGoogleDriveSyncService mockService;
  late MockSettingsDatabase mockDb;

  setUp(() {
    mockService = MockGoogleDriveSyncService();
    mockDb = MockSettingsDatabase();
    
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
      fileName: any(named: 'fileName'),
      content: any(named: 'content'),
    )).thenAnswer((_) async {});
    when(() => mockService.getLastModified(any(), any())).thenAnswer((_) async => DateTime.now());

    await syncProvider.syncCurrentFile(
      projectName: 'Test',
      fileName: 'test.md',
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
      fileName: any(named: 'fileName'),
      content: any(named: 'content'),
    )).thenThrow(Exception('Network Error'));

    await syncProvider.syncCurrentFile(
      projectName: 'Test',
      fileName: 'test.md',
      content: 'Hello',
    );

    expect(syncProvider.status, SyncStatus.error);
  });

  test('loadHistory calls service and updates history list', () async {
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);
    syncProvider = SyncProvider(service: mockService, settingsDatabase: mockDb);
    await Future.microtask(() {});

    final mockRevisions = [drive.Revision(id: 'rev-1')];
    when(() => mockService.getRevisions('MyProject', 'manuscript.md'))
        .thenAnswer((_) async => mockRevisions);

    await syncProvider.loadHistory('MyProject', 'manuscript.md');

    expect(syncProvider.history, mockRevisions);
    verify(() => mockService.getRevisions('MyProject', 'manuscript.md')).called(1);
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
            fileName: any(named: 'fileName'),
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
          fileName: 'manuscript',
          content: any(named: 'content'))).called(1);
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          fileName: 'notes',
          content: any(named: 'content'))).called(1);
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          fileName: 'stats',
          content: any(named: 'content'))).called(1);
      // categories.json / .history are never uploaded.
      verifyNever(() => mockService.syncFile(
          projectName: any(named: 'projectName'),
          fileName: 'categories',
          content: any(named: 'content')));
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
          fileName: any(named: 'fileName'),
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
            fileName: 'manuscript',
            content: any(named: 'content'),
          )).thenThrow(Exception('boom'));

      await syncProvider.runFullBackupIfDue(
        masterPath: tempDir.path,
        storageService: StorageService(),
      );

      // notes + stats still uploaded despite manuscript failing.
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          fileName: 'notes',
          content: any(named: 'content'))).called(1);
      verify(() => mockService.syncFile(
          projectName: 'Alpha',
          fileName: 'stats',
          content: any(named: 'content'))).called(1);
      verify(() => mockDb.updateSetting('last_full_backup_time', any())).called(1);
    });

    test('skips a file whose local copy is older than Drive', () async {
      await writeProject('Alpha', notes: false, stats: false);
      when(() => mockDb.getSettings())
          .thenAnswer((_) async => {'last_full_backup_time': null});
      // Drive reports a far-future modifiedTime => local is older => skip.
      when(() => mockService.getLastModified('Alpha', 'manuscript'))
          .thenAnswer((_) async => DateTime.now().toUtc().add(const Duration(days: 1)));

      await syncProvider.runFullBackupIfDue(
        masterPath: tempDir.path,
        storageService: StorageService(),
      );

      verifyNever(() => mockService.syncFile(
          projectName: 'Alpha',
          fileName: 'manuscript',
          content: any(named: 'content')));
    });
  });
}
