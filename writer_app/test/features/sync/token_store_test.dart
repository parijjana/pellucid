import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pellucid/features/sync/services/google_drive_sync_service.dart';
import 'package:pellucid/features/sync/services/token_store.dart';

class FakeSecretStore implements SecretStore {
  final Map<String, String> data = {};
  bool failWrites = false;
  bool failReads = false;
  bool corruptReads = false;
  String? failWriteOnKey;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw Exception('keychain locked');
    final v = data[key];
    return corruptReads && v != null ? '$v-x' : v;
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites || key == failWriteOnKey) throw Exception('errSecMissingEntitlement');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late FakeSecretStore secrets;
  late TokenStore store;

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  setUp(() {
    secrets = FakeSecretStore();
    store = TokenStore(secrets: secrets, prefs: prefs);
  });

  test('fresh install: nothing in prefs, round-trips through the secret store', () async {
    SharedPreferences.setMockInitialValues({});
    await store.setString(TokenStore.accessTokenKey, 'a1');
    await store.setInt(TokenStore.expiryKey, 1234);
    expect(await store.getString(TokenStore.accessTokenKey), 'a1');
    expect(await store.getInt(TokenStore.expiryKey), 1234);
    expect((await prefs()).getKeys(), isEmpty);
  });

  test('migrates every legacy key out of prefs, including the int expiry', () async {
    SharedPreferences.setMockInitialValues({
      TokenStore.accessTokenKey: 'access',
      TokenStore.refreshTokenKey: 'refresh',
      TokenStore.expiryKey: 999,
      TokenStore.clientIdKey: 'cid',
      TokenStore.clientSecretKey: 'csecret',
      'unrelated_pref': 'kept',
    });
    expect(await store.getString(TokenStore.refreshTokenKey), 'refresh');
    expect(await store.getInt(TokenStore.expiryKey), 999);
    expect(secrets.data[TokenStore.clientSecretKey], 'csecret');
    final p = await prefs();
    for (final k in TokenStore.allKeys) {
      expect(p.containsKey(k), isFalse, reason: k);
    }
    expect(p.getString('unrelated_pref'), 'kept');
  });

  test('migration is idempotent across instances', () async {
    SharedPreferences.setMockInitialValues({TokenStore.refreshTokenKey: 'r'});
    await store.getString(TokenStore.refreshTokenKey);
    final again = TokenStore(secrets: secrets, prefs: prefs);
    expect(await again.getString(TokenStore.refreshTokenKey), 'r');
    expect(secrets.data, {TokenStore.refreshTokenKey: 'r'});
  });

  test('crash after the secret write but before the prefs delete: rerun finishes it', () async {
    // Simulates the interrupted state: value already copied, plaintext still present.
    SharedPreferences.setMockInitialValues({TokenStore.refreshTokenKey: 'r'});
    secrets.data[TokenStore.refreshTokenKey] = 'r';
    expect(await store.getString(TokenStore.refreshTokenKey), 'r');
    expect((await prefs()).containsKey(TokenStore.refreshTokenKey), isFalse);
  });

  test('secret-store write failure: throws, keeps the plaintext refresh token, no fallback read', () async {
    SharedPreferences.setMockInitialValues({TokenStore.refreshTokenKey: 'r'});
    secrets.failWrites = true;
    await expectLater(store.getString(TokenStore.refreshTokenKey), throwsA(isA<TokenStorageException>()));
    expect((await prefs()).getString(TokenStore.refreshTokenKey), 'r');
    // Retried (not cached) once storage works again.
    secrets.failWrites = false;
    expect(await store.getString(TokenStore.refreshTokenKey), 'r');
    expect((await prefs()).containsKey(TokenStore.refreshTokenKey), isFalse);
  });

  test('partial failure: keys before the failing one move, the rest stay', () async {
    SharedPreferences.setMockInitialValues({
      TokenStore.accessTokenKey: 'a',
      TokenStore.refreshTokenKey: 'r',
    });
    secrets.failWriteOnKey = TokenStore.refreshTokenKey;
    await expectLater(store.getString(TokenStore.accessTokenKey), throwsA(isA<TokenStorageException>()));
    final p = await prefs();
    expect(p.containsKey(TokenStore.accessTokenKey), isFalse);
    expect(p.getString(TokenStore.refreshTokenKey), 'r');
  });

  test('read-back mismatch aborts before deleting plaintext', () async {
    SharedPreferences.setMockInitialValues({TokenStore.refreshTokenKey: 'r'});
    secrets.corruptReads = true;
    await expectLater(store.getString(TokenStore.refreshTokenKey), throwsA(isA<TokenStorageException>()));
    expect((await prefs()).getString(TokenStore.refreshTokenKey), 'r');
  });

  test('read failure after migration surfaces as TokenStorageException', () async {
    SharedPreferences.setMockInitialValues({});
    await store.setString(TokenStore.accessTokenKey, 'a');
    secrets.failReads = true;
    await expectLater(store.getString(TokenStore.accessTokenKey), throwsA(isA<TokenStorageException>()));
  });

  test('clearAll (logout) empties both the secret store and plaintext leftovers', () async {
    SharedPreferences.setMockInitialValues({TokenStore.refreshTokenKey: 'old'});
    secrets.data[TokenStore.accessTokenKey] = 'a';
    secrets.data[TokenStore.clientSecretKey] = 's';
    await store.clearAll();
    expect(secrets.data, isEmpty);
    expect((await prefs()).getKeys(), isEmpty);
    expect(await store.getString(TokenStore.refreshTokenKey), isNull);
  });

  test('sync service: unreadable secret store reads as not connected, error recorded', () async {
    SharedPreferences.setMockInitialValues({});
    secrets.failReads = true;
    final service = GoogleDriveSyncService(tokenStore: store);
    expect(await service.isLoggedIn, isFalse);
    expect(service.lastStorageError, isA<TokenStorageException>());
    secrets.failReads = false;
    await store.setString(TokenStore.accessTokenKey, 'a');
    expect(await service.isLoggedIn, isTrue);
    expect(service.lastStorageError, isNull);
  });

  test('sync service: logout clears secrets even when nothing was migrated', () async {
    SharedPreferences.setMockInitialValues({TokenStore.accessTokenKey: 'legacy'});
    secrets.data[TokenStore.clientIdKey] = 'cid';
    final service = GoogleDriveSyncService(tokenStore: store);
    await service.logout();
    expect(secrets.data, isEmpty);
    expect((await prefs()).getKeys(), isEmpty);
  });
}
