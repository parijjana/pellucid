// Slice 10 / backlog item 7: show the connected Google account locally.
// Both outcomes of about.get?fields=user are covered with a fake HTTP client.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/drive_account_label.dart';
import 'package:pellucid/features/sync/services/google_drive_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockService extends Mock implements GoogleDriveSyncService {}

class MockDb extends Mock implements SettingsDatabase {}

http.Client fakeAbout(Map<String, dynamic> body, {int status = 200, List<Uri>? seen}) {
  return MockClient((request) async {
    seen?.add(request.url);
    return http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fetchDriveAboutUser', () {
    test('name and email returned -> "Name (email)", asks for user field only', () async {
      final seen = <Uri>[];
      final user = await fetchDriveAboutUser(fakeAbout({
        'user': {'displayName': 'Ada Lovelace', 'emailAddress': 'ada@example.com'}
      }, seen: seen));
      expect(user!.label, 'Ada Lovelace (ada@example.com)');
      expect(seen.single.path, '/drive/v3/about');
      expect(seen.single.queryParameters['fields'], 'user');
    });

    test('only a display name -> that name alone', () async {
      final user = await fetchDriveAboutUser(
          fakeAbout({'user': {'displayName': 'Ada'}}));
      expect(user!.label, 'Ada');
    });

    test('user without name or email -> null (caller asks the user)', () async {
      expect(await fetchDriveAboutUser(fakeAbout({'user': {'kind': 'drive#user'}})), isNull);
    });

    test('HTTP error -> null, no throw', () async {
      expect(await fetchDriveAboutUser(fakeAbout({'error': {}}, status: 403)), isNull);
    });
  });

  group('SyncProvider account label', () {
    late MockService service;
    late MockDb db;
    var loggedIn = false;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      loggedIn = false;
      service = MockService();
      db = MockDb();
      when(() => db.getMirroredProjects()).thenAnswer((_) async => <String>{});
      when(() => db.getSettings()).thenAnswer((_) async => {'last_synced_time': null});
      when(() => db.updateSetting(any(), any())).thenAnswer((_) async {});
      when(() => service.isLoggedIn).thenAnswer((_) async => loggedIn);
      when(() => service.login()).thenAnswer((_) async => loggedIn = true);
      when(() => service.logout()).thenAnswer((_) async => loggedIn = false);
    });

    test('Google answers: label shown and persisted locally', () async {
      when(() => service.fetchAccountUser()).thenAnswer((_) async =>
          const DriveAccountUser(displayName: 'Ada', emailAddress: 'ada@example.com'));
      final sync = SyncProvider(service: service, settingsDatabase: db);
      await sync.login();
      expect(sync.accountLabel, 'Ada (ada@example.com)');
      expect(await DriveAccountLabelStore().read(), 'Ada (ada@example.com)');
    });

    test('Google withholds: no label until the user names it; editable; survives restart', () async {
      when(() => service.fetchAccountUser()).thenAnswer((_) async => null);
      final sync = SyncProvider(service: service, settingsDatabase: db);
      await sync.login();
      expect(sync.accountLabel, isNull);

      await sync.setAccountLabel('Personal Drive');
      expect(sync.accountLabel, 'Personal Drive');
      await sync.setAccountLabel('  Work Drive ');
      expect(sync.accountLabel, 'Work Drive');

      final restarted = SyncProvider(service: service, settingsDatabase: db);
      await Future<void>.delayed(Duration.zero);
      expect(restarted.accountLabel, 'Work Drive');
    });

    test('empty name clears; disconnect forgets the label', () async {
      when(() => service.fetchAccountUser()).thenAnswer((_) async => null);
      final sync = SyncProvider(service: service, settingsDatabase: db);
      await sync.login();
      await sync.setAccountLabel('Personal Drive');
      await sync.setAccountLabel('   ');
      expect(sync.accountLabel, isNull);

      await sync.setAccountLabel('Personal Drive');
      await sync.logout();
      expect(sync.accountLabel, isNull);
    });
  });
}
