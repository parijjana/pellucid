import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'oauth_helper_factory.dart';
import '../models/logical_file.dart';

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

  // iOS OAuth clients are public (no secret) and are a separate Google Cloud
  // Console client from the desktop one, so they get their own dart-define.
  static const String _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: 'YOUR_GOOGLE_IOS_CLIENT_ID');

  drive.DriveApi? _driveApi;

  Future<bool> get isLoggedIn async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) != null;
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

    // iOS has its own (secret-less, public) OAuth client; desktop platforms
    // keep using the client id/secret pair they always have.
    final clientId = customClientId ?? (Platform.isIOS ? _iosClientId : _clientId);
    final clientSecret = customClientSecret ?? _clientSecret;

    final helper = createOAuthHelper(
      clientId: clientId,
      clientSecret: clientSecret,
      scopes: [drive.DriveApi.driveFileScope, 'email', 'profile'],
    );

    final tokens = await helper.authenticate();
    if (tokens != null && tokens['access_token'] != null) {
      await prefs.setString(_tokenKey, tokens['access_token']);
      if (tokens['refresh_token'] != null) {
        await prefs.setString(_refreshTokenKey, tokens['refresh_token']);
      }
      final expiresIn = tokens['expires_in'] ?? 3600;
      await prefs.setInt(_expiryKey, DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000) as int);

      _driveApi = drive.DriveApi(GoogleAuthClient(tokens['access_token']));
    }
  }

  Future<void> logout() async {
    _driveApi = null;

    // Best-effort revoke of the refresh token at Google before clearing it
    // locally, so the grant is invalidated server-side too. Failures ignored.
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
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

    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiryKey);
    await prefs.remove(_clientIdKey);
    await prefs.remove(_clientSecretKey);
  }

  Future<bool> _isTokenExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = prefs.getInt(_expiryKey);
    if (expiry == null) return true;
    // 1-minute buffer before actual expiry
    return DateTime.now().millisecondsSinceEpoch > (expiry - 60000);
  }

  Future<bool> refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken == null) return false;

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
        final expiresIn = data['expires_in'] ?? 3600;

        await prefs.setString(_tokenKey, newAccessToken);
        await prefs.setInt(_expiryKey, DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000) as int);

        if (data['refresh_token'] != null) {
          await prefs.setString(_refreshTokenKey, data['refresh_token']);
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
    required LogicalFile file,
    required String content,
  }) async {
    final api = await _getApi();
    if (api == null) {
      if (kDebugMode) print('Drive API not initialized');
      return;
    }

    final driveFileName = file.driveFileName;

    try {
      final vaultId = await _getOrCreateFolder(api, _vaultFolderName);
      final projectId = await _getOrCreateFolder(api, projectName, parentId: vaultId);

      final existingFile = await _findFile(api, driveFileName, parentId: projectId);

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
        if (kDebugMode) print('Updated file in Drive: $driveFileName');
      } else {
        await api.files.create(
          drive.File(
            name: driveFileName,
            parents: [projectId],
            mimeType: 'text/markdown',
          ),
          uploadMedia: media,
        );
        if (kDebugMode) print('Created file in Drive: $driveFileName');
      }
    } catch (e) {
      if (kDebugMode) print('Error syncing to Drive: $e');
      rethrow;
    }
  }

  Future<List<drive.Revision>> getRevisions(String projectName, LogicalFile file) async {
    final api = await _getApi();
    if (api == null) return [];

    final vaultId = await _findFile(api, _vaultFolderName, isFolder: true);
    if (vaultId == null) return [];

    final projectId = await _findFile(api, projectName, parentId: vaultId.id, isFolder: true);
    if (projectId == null) return [];

    final driveFile = await _findFile(api, file.driveFileName, parentId: projectId.id);
    if (driveFile == null) return [];

    final result = await api.revisions.list(driveFile.id!);
    return result.revisions ?? [];
  }

  Future<String> getRevisionContent(String revisionId, String projectName, LogicalFile file) async {
    final api = await _getApi();
    if (api == null) return '';

    final vaultId = await _findFile(api, _vaultFolderName, isFolder: true);
    if (vaultId == null) return '';

    final projectId = await _findFile(api, projectName, parentId: vaultId.id, isFolder: true);
    if (projectId == null) return '';

    final driveFile = await _findFile(api, file.driveFileName, parentId: projectId.id);
    if (driveFile == null) return '';

    final response = await api.revisions.get(driveFile.id!, revisionId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final contentBytes = await response.stream.fold<List<int>>([], (p, e) => p..addAll(e));
    return utf8.decode(contentBytes);
  }

  Future<DateTime?> getLastModified(String projectName, LogicalFile file) async {
    final api = await _getApi();
    if (api == null) return null;

    final vaultId = await _findFile(api, _vaultFolderName, isFolder: true);
    if (vaultId == null) return null;

    final projectId = await _findFile(api, projectName, parentId: vaultId.id, isFolder: true);
    if (projectId == null) return null;

    final driveFile = await _findFile(api, file.driveFileName, parentId: projectId.id);
    if (driveFile == null) return null;

    final result = await api.files.get(driveFile.id!, $fields: 'modifiedTime') as drive.File;
    return result.modifiedTime;
  }

  // ---------------------------------------------------------------------------
  // Raw, filename-based helpers used ONLY by the one-time manuscript filename
  // migration (see lib/features/sync/services/manuscript_migration.dart and
  // ManuscriptMigrationRunner in sync_provider.dart). These bypass
  // [LogicalFile] deliberately: the migration's whole job is to reconcile a
  // legacy raw filename (`manuscript.md.md`) that has no [LogicalFile]
  // mapping with the canonical one. Nothing else should call these — every
  // other caller must go through the [LogicalFile]-typed methods above.
  // ---------------------------------------------------------------------------

  /// Looks up an exact filename inside a project's Drive folder. Returns the
  /// full [drive.File] (including `id` and `modifiedTime`) or null if it
  /// doesn't exist. Does not create the vault/project folders if missing —
  /// if there's no project folder yet, there's nothing to migrate.
  Future<drive.File?> findRawFileInProject(String projectName, String exactFileName) async {
    final api = await _getApi();
    if (api == null) return null;

    final vaultId = await _findFile(api, _vaultFolderName, isFolder: true);
    if (vaultId == null) return null;

    final projectId = await _findFile(api, projectName, parentId: vaultId.id, isFolder: true);
    if (projectId == null) return null;

    return _findFile(api, exactFileName, parentId: projectId.id, $fields: 'files(id, name, modifiedTime)');
  }

  /// Downloads a file's full content by id.
  Future<String?> downloadFileContent(String fileId) async {
    final api = await _getApi();
    if (api == null) return null;

    final response = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final contentBytes = await response.stream.fold<List<int>>([], (p, e) => p..addAll(e));
    return utf8.decode(contentBytes);
  }

  /// Overwrites an EXISTING file's content via `files.update` (never
  /// delete-then-create). Drive automatically retains the prior revision on
  /// update, so whatever content the file held immediately before this call
  /// remains recoverable through Drive's revision history even though this
  /// call overwrites the "live" content.
  Future<void> overwriteFileContent(String fileId, String content) async {
    final api = await _getApi();
    if (api == null) throw StateError('Drive API not initialized');

    final bytes = utf8.encode(content);
    final media = drive.Media(Stream.value(bytes), bytes.length);
    await api.files.update(drive.File(), fileId, uploadMedia: media);
  }

  /// Creates a new file with the given exact name and content inside a
  /// project's Drive folder (creating the vault/project folders if needed),
  /// returning the new file's id.
  Future<String> createRawFileInProject(String projectName, String exactFileName, String content) async {
    final api = await _getApi();
    if (api == null) throw StateError('Drive API not initialized');

    final vaultId = await _getOrCreateFolder(api, _vaultFolderName);
    final projectId = await _getOrCreateFolder(api, projectName, parentId: vaultId);

    final bytes = utf8.encode(content);
    final media = drive.Media(Stream.value(bytes), bytes.length);
    final result = await api.files.create(
      drive.File(name: exactFileName, parents: [projectId], mimeType: 'text/markdown'),
      uploadMedia: media,
    );
    return result.id!;
  }

  /// Lists every project folder name directly under the vault folder, with
  /// full paging (unlike [_findFile], which intentionally only needs the
  /// first match for a single-name lookup). Used to sweep every project in
  /// the vault during migration. Returns an empty list if the vault doesn't
  /// exist yet (nothing to migrate).
  Future<List<String>> listProjectNames() async {
    final api = await _getApi();
    if (api == null) return [];

    final vaultId = await _findFile(api, _vaultFolderName, isFolder: true);
    if (vaultId == null) return [];

    final names = <String>[];
    String? pageToken;
    do {
      final result = await api.files.list(
        q: "'${vaultId.id}' in parents and trashed = false and mimeType = 'application/vnd.google-apps.folder'",
        $fields: 'nextPageToken, files(id, name)',
        pageToken: pageToken,
      );
      names.addAll((result.files ?? []).map((f) => f.name!));
      pageToken = result.nextPageToken;
    } while (pageToken != null);

    return names;
  }

  Future<drive.DriveApi?> _getApi() async {
    if (_driveApi != null) {
      final isExpired = await _isTokenExpired();
      if (!isExpired) return _driveApi;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      final isExpired = await _isTokenExpired();
      if (isExpired) {
        final success = await refreshAccessToken();
        if (!success) return null;
      }

      final freshToken = prefs.getString(_tokenKey);
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

  Future<drive.File?> _findFile(
    drive.DriveApi api,
    String name, {
    String? parentId,
    bool isFolder = false,
    String $fields = 'files(id, name)',
  }) async {
    final escapedName = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    String query = "name = '$escapedName' and trashed = false";
    if (parentId != null) query += " and '$parentId' in parents";
    if (isFolder) query += " and mimeType = 'application/vnd.google-apps.folder'";

    final result = await api.files.list(q: query, $fields: $fields);
    return (result.files?.isNotEmpty ?? false) ? result.files!.first : null;
  }
}
