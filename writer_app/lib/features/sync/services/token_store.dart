import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when the OS secret store (Keychain / Credential Manager) cannot be
/// read or written. Callers must treat this as "not connected" and let the
/// user reconnect; they must never fall back to plaintext storage.
class TokenStorageException implements Exception {
  final String message;
  final Object? cause;
  TokenStorageException(this.message, [this.cause]);

  @override
  String toString() => 'TokenStorageException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Minimal key/value secret store, so tests can swap in a fake.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [SecretStore] over flutter_secure_storage: the Keychain on macOS/iOS,
/// an AES file keyed from Credential Manager (DPAPI, per user) on Windows.
///
/// macOS: the data-protection keychain needs the
/// `com.apple.application-identifier` entitlement, which only provisioned
/// builds carry (App Store / TestFlight exports embed it; a local `flutter
/// run`, `flutter build macos` or Development-signed export does not, and gets
/// errSecMissingEntitlement, -34018). Those builds use the legacy login
/// keychain instead: still the Keychain, never plaintext. The mode is probed
/// once per launch and is fixed for a given binary, so items never straddle
/// the two. See lessons_learnt/flutter-secure-storage-macos-sandbox.md.
class PlatformSecretStore implements SecretStore {
  static const int _errSecMissingEntitlement = -34018;
  static const String _probeKey = 'pellucid_keychain_probe';

  static const FlutterSecureStorage _dataProtection = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: true),
  );
  static const FlutterSecureStorage _legacyKeychain = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static Future<FlutterSecureStorage>? _selected;

  PlatformSecretStore();

  Future<FlutterSecureStorage> get _storage => _selected ??= _select();

  static Future<FlutterSecureStorage> _select() async {
    if (kIsWeb || !Platform.isMacOS) return _dataProtection;
    try {
      await _dataProtection.write(key: _probeKey, value: '1');
      await _dataProtection.delete(key: _probeKey);
      return _dataProtection;
    } on PlatformException catch (e) {
      if (e.details == _errSecMissingEntitlement) {
        if (kDebugMode) print('TokenStore: unprovisioned build, using the login keychain');
        return _legacyKeychain;
      }
      _selected = null; // transient failure (e.g. locked keychain): probe again later
      rethrow;
    }
  }

  @override
  Future<String?> read(String key) async => (await _storage).read(key: key);

  @override
  Future<void> write(String key, String value) async => (await _storage).write(key: key, value: value);

  @override
  Future<void> delete(String key) async => (await _storage).delete(key: key);
}

/// Holds the Google Drive OAuth credentials in the OS secret store.
///
/// Older installs kept them in SharedPreferences (a plain plist / JSON file).
/// The first access migrates each key: write to the secret store, read it
/// back, and only then remove the plaintext copy. A crash at any point leaves
/// the value in at least one place, and a rerun simply repeats the copy, so
/// the refresh token is never lost. Until migration has succeeded nothing is
/// read from or written to prefs except to finish it.
class TokenStore {
  static const String accessTokenKey = 'google_drive_token';
  static const String refreshTokenKey = 'google_drive_refresh_token';
  static const String expiryKey = 'google_drive_token_expiry';
  static const String clientIdKey = 'google_client_id_pref';
  static const String clientSecretKey = 'google_client_secret_pref';

  /// A user-entered custom OAuth client secret (Settings). Kept apart from
  /// [allKeys] so Drive logout does not wipe the user's own configuration.
  static const String customClientSecretKey = 'google_custom_client_secret';

  static const List<String> allKeys = [
    accessTokenKey,
    refreshTokenKey,
    expiryKey,
    clientIdKey,
    clientSecretKey,
  ];

  final SecretStore _secrets;
  final Future<SharedPreferences> Function() _prefs;
  Future<void>? _migration;

  TokenStore({SecretStore? secrets, Future<SharedPreferences> Function()? prefs})
      : _secrets = secrets ?? PlatformSecretStore(),
        _prefs = prefs ?? SharedPreferences.getInstance;

  Future<String?> getString(String key) async {
    await _ensureMigrated();
    return _guard('read $key', () => _secrets.read(key));
  }

  Future<int?> getInt(String key) async {
    final value = await getString(key);
    return value == null ? null : int.tryParse(value);
  }

  Future<void> setString(String key, String value) async {
    await _ensureMigrated();
    await _guard('write $key', () => _secrets.write(key, value));
  }

  Future<void> setInt(String key, int value) => setString(key, value.toString());

  Future<void> remove(String key) async {
    await _ensureMigrated();
    await _guard('delete $key', () => _secrets.delete(key));
  }

  /// Logout: clears every credential from both the secret store and any
  /// plaintext leftovers, whether or not migration ever completed.
  Future<void> clearAll() async {
    final prefs = await _guard('open prefs', _prefs);
    for (final key in allKeys) {
      await prefs.remove(key);
    }
    for (final key in allKeys) {
      await _guard('delete $key', () => _secrets.delete(key));
    }
    _migration = Future.value();
  }

  Future<void> _ensureMigrated() {
    // A failed migration is retried on the next access rather than cached.
    return _migration ??= _migrate().catchError((Object e) {
      _migration = null;
      throw e;
    });
  }

  Future<void> _migrate() async {
    final prefs = await _guard('open prefs', _prefs);
    for (final key in allKeys) {
      final Object? legacy = prefs.get(key);
      if (legacy == null) continue;
      final value = legacy.toString();
      await _guard('migrate $key', () => _secrets.write(key, value));
      final readBack = await _guard('verify $key', () => _secrets.read(key));
      if (readBack != value) {
        throw TokenStorageException('migrate $key: read-back mismatch');
      }
      await prefs.remove(key);
      if (kDebugMode) print('TokenStore: migrated $key out of SharedPreferences');
    }
  }

  Future<T> _guard<T>(String what, Future<T> Function() op) async {
    try {
      return await op();
    } on TokenStorageException {
      rethrow;
    } catch (e) {
      throw TokenStorageException(what, e);
    }
  }
}
