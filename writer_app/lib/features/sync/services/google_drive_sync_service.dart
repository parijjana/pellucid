import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'desktop_oauth_helper.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(String accessToken)
      : _headers = {'Authorization': 'Bearer $accessToken'};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class GoogleDriveSyncService {
  static const String _vaultFolderName = 'Pellucid Vault';
  static const String _tokenKey = 'google_drive_token';
  static const String _refreshTokenKey = 'google_drive_refresh_token';
  static const String _expiryKey = 'google_drive_token_expiry';
  static const String _clientIdKey = 'google_client_id_pref';
  static const String _clientSecretKey = 'google_client_secret_pref';

  static const String _clientId = String.fromEnvironment('GOOGLE_CLIENT_ID', defaultValue: 'YOUR_GOOGLE_CLIENT_ID');
  static const String _clientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET', defaultValue: 'YOUR_GOOGLE_CLIENT_SECRET');

  /// Keychain-backed storage for the OAuth tokens (macOS/iOS Keychain).
  final FlutterSecureStorage _secureStorage;

  GoogleDriveSyncService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  drive.DriveApi? _driveApi;

  /// One-time migration so already-signed-in users are NOT logged out when the
  /// app moves the OAuth tokens from plaintext SharedPreferences into the
  /// Keychain. If secure storage already holds a token, or the legacy prefs
  /// have nothing, this is a cheap no-op. After a successful copy the legacy
  /// prefs keys are deleted so tokens no longer live in plaintext.
  Future<void> _migrateTokensIfNeeded() async {
    final existing = await _secureStorage.read(key: _tokenKey);
    if (existing != null) return; // Already migrated / already in Keychain.

    final prefs = await SharedPreferences.getInstance();
    final oldToken = prefs.getString(_tokenKey);
    if (oldToken == null) return; // Nothing to migrate.

    await _secureStorage.write(key: _tokenKey, value: oldToken);
    final oldRefresh = prefs.getString(_refreshTokenKey);
    if (oldRefresh != null) {
      await _secureStorage.write(key: _refreshTokenKey, value: oldRefresh);
    }
    final oldExpiry = prefs.getInt(_expiryKey);
    if (oldExpiry != null) {
      await _secureStorage.write(key: _expiryKey, value: oldExpiry.toString());
    }

    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiryKey);
  }

  Future<bool> get isLoggedIn async {
    await _migrateTokensIfNeeded();
    return (await _secureStorage.read(key: _tokenKey)) != null;
  }

  Future<void> login({String? customClientId, String? customClientSecret}) async {
    final prefs = await SharedPreferences.getInstance();
    if (customClientId != null) {
      await prefs.setString(_clientIdKey, customClientId);
    } else {
      await prefs.remove(_clientIdKey);
    }
    if (customClientSecret != null) {
      await prefs.setString(_clientSecretKey, customClientSecret);
    } else {
      await prefs.remove(_clientSecretKey);
    }

    final clientId = customClientId ?? _clientId;
    final clientSecret = customClientSecret ?? _clientSecret;

    final helper = DesktopOAuthHelper(
      clientId: clientId,
      clientSecret: clientSecret,
      scopes: [drive.DriveApi.driveFileScope, 'email', 'profile'],
    );

    final tokens = await helper.authenticate();
    if (tokens != null && tokens['access_token'] != null) {
      await _secureStorage.write(key: _tokenKey, value: tokens['access_token']);
      if (tokens['refresh_token'] != null) {
        await _secureStorage.write(
            key: _refreshTokenKey, value: tokens['refresh_token']);
      }
      final expiresIn = (tokens['expires_in'] ?? 3600) as int;
      final expiryMs =
          DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
      await _secureStorage.write(key: _expiryKey, value: expiryMs.toString());

      _driveApi = drive.DriveApi(GoogleAuthClient(tokens['access_token']));
    }
  }

  Future<void> logout() async {
    _driveApi = null;

    // Best-effort revoke of the refresh token at Google before clearing it
    // locally, so the grant is invalidated server-side too. Failures ignored.
    await _migrateTokensIfNeeded();
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken != null) {
      try {
        await http.post(
          Uri.parse('https://oauth2.googleapis.com/revoke'),
          body: {'token': refreshToken},
        );
      } catch (e) {
        if (kDebugMode) print('Failed to revoke refresh token: $e');
      }
    }

    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _expiryKey);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clientIdKey);
    await prefs.remove(_clientSecretKey);
  }

  Future<bool> _isTokenExpired() async {
    final expiryStr = await _secureStorage.read(key: _expiryKey);
    final expiry = expiryStr != null ? int.tryParse(expiryStr) : null;
    if (expiry == null) return true;
    // 1-minute buffer before actual expiry
    return DateTime.now().millisecondsSinceEpoch > (expiry - 60000);
  }

  Future<bool> refreshAccessToken() async {
    await _migrateTokensIfNeeded();
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken == null) return false;

    final prefs = await SharedPreferences.getInstance();

    final clientId = prefs.getString(_clientIdKey) ?? _clientId;
    final clientSecret = prefs.getString(_clientSecretKey) ?? _clientSecret;

    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access_token'];
        final expiresIn = (data['expires_in'] ?? 3600) as int;
        final expiryMs =
            DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;

        await _secureStorage.write(key: _tokenKey, value: newAccessToken);
        await _secureStorage.write(key: _expiryKey, value: expiryMs.toString());

        if (data['refresh_token'] != null) {
          await _secureStorage.write(
              key: _refreshTokenKey, value: data['refresh_token']);
        }
        return true;
      }
    } catch (e) {
      if (kDebugMode) print('Failed to refresh access token: $e');
    }
    return false;
  }

  Future<void> syncFile({
    required String projectName,
    required String fileName,
    required String content,
  }) async {
    final api = await _getApi();
    if (api == null) {
      if (kDebugMode) print('Drive API not initialized');
      return;
    }

    try {
      final vaultId = await _getOrCreateFolder(api, _vaultFolderName);
      final projectId = await _getOrCreateFolder(api, projectName, parentId: vaultId);
      
      final existingFile = await _findFile(api, '$fileName.md', parentId: projectId);
      
      final bytes = utf8.encode(content);
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
      );

      if (existingFile != null) {
        await api.files.update(
          drive.File(),
          existingFile.id!,
          uploadMedia: media,
        );
        if (kDebugMode) print('Updated file in Drive: $fileName');
      } else {
        await api.files.create(
          drive.File(
            name: '$fileName.md',
            parents: [projectId],
            mimeType: 'text/markdown',
          ),
          uploadMedia: media,
        );
        if (kDebugMode) print('Created file in Drive: $fileName');
      }
    } catch (e) {
      if (kDebugMode) print('Error syncing to Drive: $e');
      rethrow;
    }
  }

  Future<List<drive.Revision>> getRevisions(String projectName, String fileName) async {
    final api = await _getApi();
    if (api == null) return [];

    final vaultId = await _findFile(api, _vaultFolderName, isFolder: true);
    if (vaultId == null) return [];

    final projectId = await _findFile(api, projectName, parentId: vaultId.id, isFolder: true);
    if (projectId == null) return [];

    final file = await _findFile(api, '$fileName.md', parentId: projectId.id);
    if (file == null) return [];

    final result = await api.revisions.list(file.id!);
    return result.revisions ?? [];
  }

  Future<String> getRevisionContent(String revisionId, String projectName, String fileName) async {
    final api = await _getApi();
    if (api == null) return '';

    final vaultId = await _findFile(api, _vaultFolderName, isFolder: true);
    if (vaultId == null) return '';

    final projectId = await _findFile(api, projectName, parentId: vaultId.id, isFolder: true);
    if (projectId == null) return '';

    final file = await _findFile(api, '$fileName.md', parentId: projectId.id);
    if (file == null) return '';

    final response = await api.revisions.get(file.id!, revisionId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final contentBytes = await response.stream.fold<List<int>>([], (p, e) => p..addAll(e));
    return utf8.decode(contentBytes);
  }

  Future<DateTime?> getLastModified(String projectName, String fileName) async {
    final api = await _getApi();
    if (api == null) return null;

    final vaultId = await _findFile(api, _vaultFolderName, isFolder: true);
    if (vaultId == null) return null;

    final projectId = await _findFile(api, projectName, parentId: vaultId.id, isFolder: true);
    if (projectId == null) return null;

    final file = await _findFile(api, '$fileName.md', parentId: projectId.id);
    if (file == null) return null;

    final result = await api.files.get(file.id!, $fields: 'modifiedTime') as drive.File;
    return result.modifiedTime;
  }

  Future<drive.DriveApi?> _getApi() async {
    if (_driveApi != null) {
      final isExpired = await _isTokenExpired();
      if (!isExpired) return _driveApi;
    }
    
    await _migrateTokensIfNeeded();
    final token = await _secureStorage.read(key: _tokenKey);
    if (token != null) {
      final isExpired = await _isTokenExpired();
      if (isExpired) {
        final success = await refreshAccessToken();
        if (!success) return null;
      }

      final freshToken = await _secureStorage.read(key: _tokenKey);
      _driveApi = drive.DriveApi(GoogleAuthClient(freshToken!));
      return _driveApi;
    }
    return null;
  }

  Future<String> _getOrCreateFolder(drive.DriveApi api, String name, {String? parentId}) async {
    final existing = await _findFile(api, name, parentId: parentId, isFolder: true);
    if (existing != null) return existing.id!;

    final folder = drive.File(
      name: name,
      mimeType: 'application/vnd.google-apps.folder',
      parents: parentId != null ? [parentId] : null,
    );

    final result = await api.files.create(folder);
    return result.id!;
  }

  Future<drive.File?> _findFile(drive.DriveApi api, String name, {String? parentId, bool isFolder = false}) async {
    final escapedName = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    String query = "name = '$escapedName' and trashed = false";
    if (parentId != null) query += " and '$parentId' in parents";
    if (isFolder) query += " and mimeType = 'application/vnd.google-apps.folder'";

    final result = await api.files.list(q: query, $fields: 'files(id, name)');
    return (result.files?.isNotEmpty ?? false) ? result.files!.first : null;
  }
}
