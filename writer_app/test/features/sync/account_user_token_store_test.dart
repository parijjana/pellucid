// Description: Slices 10 + 12 together: the account-name lookup (about.get)
// reads the access token from the TokenStore (OS secret store), not from
// SharedPreferences, where it no longer lives.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pellucid/features/sync/services/drive_account_label.dart';
import 'package:pellucid/features/sync/services/google_drive_sync_service.dart';
import 'package:pellucid/features/sync/services/token_store.dart';

class _Secrets implements SecretStore {
  final Map<String, String> data = {};
  bool failReads = false;
  @override
  Future<String?> read(String key) async {
    if (failReads) throw Exception('keychain locked');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late _Secrets secrets;
  late List<http.Client> calls;
  late GoogleDriveSyncService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({}); // nothing left in plaintext prefs
    secrets = _Secrets();
    calls = [];
    service = GoogleDriveSyncService(
      tokenStore: TokenStore(secrets: secrets, prefs: SharedPreferences.getInstance),
      aboutUser: (client) async {
        calls.add(client);
        return const DriveAccountUser(displayName: 'Ada', emailAddress: 'ada@example.com');
      },
    );
  });

  test('uses the token held in the secret store', () async {
    secrets.data[TokenStore.accessTokenKey] = 'tok';
    secrets.data[TokenStore.expiryKey] =
        '${DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch}';
    final user = await service.fetchAccountUser();
    expect(calls, hasLength(1));
    expect(calls.single, isA<GoogleAuthClient>());
    expect(user?.label, 'Ada (ada@example.com)');
  });

  test('no token anywhere: no lookup', () async {
    expect(await service.fetchAccountUser(), isNull);
    expect(calls, isEmpty);
  });

  test('secret store failure: no label, error recorded, no throw', () async {
    secrets.failReads = true;
    expect(await service.fetchAccountUser(), isNull);
    expect(calls, isEmpty);
    expect(service.lastStorageError, isNotNull);
  });
}
