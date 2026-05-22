import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/google_drive_sync_service.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';

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

  test('syncCurrentFile updates status to success on success', () async {
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);
    // Re-init with logged in status
    syncProvider = SyncProvider(service: mockService);
    // Need to wait for _checkLoginStatus to finish
    await Future.microtask(() {}); 

    when(() => mockService.syncFile(
      projectName: any(named: 'projectName'),
      fileName: any(named: 'fileName'),
      content: any(named: 'content'),
    )).thenAnswer((_) async {});

    await syncProvider.syncCurrentFile(
      projectName: 'Test',
      fileName: 'test.md',
      content: 'Hello',
    );

    expect(syncProvider.status, SyncStatus.success);
  });

  test('syncCurrentFile updates status to error on failure', () async {
    when(() => mockService.isLoggedIn).thenAnswer((_) async => true);
    syncProvider = SyncProvider(service: mockService);
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
}
