import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  static const String _clientId = 'YOUR_GOOGLE_CLIENT_ID';
  static const String _clientSecret = 'YOUR_GOOGLE_CLIENT_SECRET';

  drive.DriveApi? _driveApi;

  Future<bool> get isLoggedIn async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) != null;
  }

  Future<void> login() async {
    final helper = DesktopOAuthHelper(
      clientId: _clientId,
      clientSecret: _clientSecret,
      scopes: [drive.DriveApi.driveFileScope, 'email', 'profile'],
    );

    final tokens = await helper.authenticate();
    if (tokens != null && tokens['access_token'] != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, tokens['access_token']);
      _driveApi = drive.DriveApi(GoogleAuthClient(tokens['access_token']));
    }
  }

  Future<void> logout() async {
    _driveApi = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
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
      
      final media = drive.Media(
        Stream.value(utf8.encode(content)),
        content.length,
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
    if (_driveApi != null) return _driveApi;
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      _driveApi = drive.DriveApi(GoogleAuthClient(token));
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
    String query = "name = '$name' and trashed = false";
    if (parentId != null) query += " and '$parentId' in parents";
    if (isFolder) query += " and mimeType = 'application/vnd.google-apps.folder'";

    final result = await api.files.list(q: query, $fields: 'files(id, name)');
    return (result.files?.isNotEmpty ?? false) ? result.files!.first : null;
  }
}
