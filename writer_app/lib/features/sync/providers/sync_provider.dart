import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/google_drive_sync_service.dart';
import '../../settings/providers/settings_database.dart';

enum SyncStatus { idle, syncing, success, error }

class SyncProvider with ChangeNotifier {
  final GoogleDriveSyncService _service;
  final SettingsDatabase _db;
  
  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  DateTime? _lastSynced;
  DateTime? get lastSynced => _lastSynced;

  List<drive.Revision> _history = [];
  List<drive.Revision> get history => _history;

  SyncProvider({GoogleDriveSyncService? service, SettingsDatabase? settingsDatabase}) 
      : _service = service ?? GoogleDriveSyncService(),
        _db = settingsDatabase ?? SettingsDatabase.instance {
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    _isLoggedIn = await _service.isLoggedIn;
    final settings = await _db.getSettings();
    final lastSyncedStr = settings['last_synced_time'];
    if (lastSyncedStr != null) {
      _lastSynced = DateTime.tryParse(lastSyncedStr);
    }
    notifyListeners();
  }

  Future<bool> login({String? clientId, String? clientSecret}) async {
    try {
      await _service.login(customClientId: clientId, customClientSecret: clientSecret);
      await _checkLoginStatus();
      return _isLoggedIn;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    await _service.logout();
    _isLoggedIn = false;
    _lastSynced = null;
    await _db.updateSetting('last_synced_time', null);
    notifyListeners();
  }

  Future<void> syncCurrentFile({
    required String projectName,
    required String fileName,
    required String content,
  }) async {
    if (!_isLoggedIn) return;

    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      await _service.syncFile(
        projectName: projectName,
        fileName: fileName,
        content: content,
      );
      _status = SyncStatus.success;
      await refreshLastSynced(projectName, fileName);
    } catch (e) {
      _status = SyncStatus.error;
    } finally {
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        if (_status != SyncStatus.syncing) {
          _status = SyncStatus.idle;
          notifyListeners();
        }
      });
    }
  }

  Future<void> syncNotes({
    required String projectName,
    required String notesJson,
  }) async {
    if (!_isLoggedIn) return;

    try {
      await _service.syncFile(
        projectName: projectName,
        fileName: 'notes',
        content: notesJson,
      );
      await refreshLastSynced(projectName, 'notes');
    } catch (e) {
      if (kDebugMode) print('Failed to sync notes: $e');
    }
  }

  Future<void> refreshLastSynced(String projectName, String fileName) async {
    final driveTime = await _service.getLastModified(projectName, fileName);
    if (driveTime != null) {
      _lastSynced = driveTime.toLocal();
      await _db.updateSetting('last_synced_time', _lastSynced!.toIso8601String());
      notifyListeners();
    }
  }

  Future<void> loadHistory(String projectName, String fileName) async {
    if (!_isLoggedIn) return;
    try {
      _history = await _service.getRevisions(projectName, fileName);
      notifyListeners();
    } catch (e) {
      _history = [];
      notifyListeners();
    }
  }

  Future<String> getVersionContent(String revisionId, String projectName, String fileName) async {
    return await _service.getRevisionContent(revisionId, projectName, fileName);
  }

  Future<void> syncStats({
    required String projectName,
    required String statsJson,
  }) async {
    if (!_isLoggedIn) return;

    try {
      await _service.syncFile(
        projectName: projectName,
        fileName: 'stats',
        content: statsJson,
      );
      await refreshLastSynced(projectName, 'stats');
    } catch (e) {
      if (kDebugMode) print('Failed to sync stats: $e');
    }
  }

  Future<String?> getLatestContent({
    required String projectName,
    required String fileName,
  }) async {
    if (!_isLoggedIn) return null;
    try {
      final revisions = await _service.getRevisions(projectName, fileName);
      if (revisions.isEmpty) return null;
      final latestRevision = revisions.last;
      if (latestRevision.id == null) return null;
      return await _service.getRevisionContent(latestRevision.id!, projectName, fileName);
    } catch (e) {
      if (kDebugMode) print('Failed to get latest content: $e');
      return null;
    }
  }
}
