import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/google_drive_sync_service.dart';
import '../../settings/providers/settings_database.dart';
import '../../editor/providers/storage_service.dart';

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

  /// Minimum time between full-library backup sweeps.
  static const Duration fullBackupInterval = Duration(hours: 24);

  // Guards against overlapping sweeps (e.g. startup run + hourly timer).
  bool _fullBackupInProgress = false;
  bool get isFullBackupInProgress => _fullBackupInProgress;

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

  // ---------------------------------------------------------------------------
  // Full-library backup sweep (one-way, local -> Drive only).
  //
  // Separate from the edit-driven per-file sync. Uploads every project's core
  // files from the local master directory to Drive, but only when a file is
  // missing in Drive or the local copy is at/after Drive's modifiedTime. Local
  // is always the source of truth; this path NEVER pulls Drive -> local.
  // ---------------------------------------------------------------------------

  /// Local filename -> Drive logical file name, matching the editor's Drive
  /// schema exactly so no duplicate files are ever created. `.history/`
  /// snapshots and `categories.json` are intentionally excluded.
  static const Map<String, String> fullBackupFileMap = {
    'document.md': 'manuscript',
    'notes.json': 'notes',
    'stats.json': 'stats',
  };

  /// Pure decision for the "is this file out of date / should upload" check.
  ///
  /// Uploads when Drive has no copy (`driveModifiedTime == null`) OR the local
  /// file's last-modified time is at or after Drive's modifiedTime. Biased
  /// toward uploading: only a strictly-older local copy is skipped. Comparison
  /// is done in UTC so local-vs-Drive time zones can't cause a false skip.
  static bool shouldUploadFile({
    required DateTime localMtime,
    required DateTime? driveModifiedTime,
  }) {
    if (driveModifiedTime == null) return true;
    return !localMtime.toUtc().isBefore(driveModifiedTime.toUtc());
  }

  /// Runs a full backup sweep if at least [fullBackupInterval] has elapsed since
  /// the last one (or none has ever run). No-op if not logged in or if the
  /// sweep is already running. Designed to be called fire-and-forget from app
  /// startup and from a periodic timer; it does not touch [SyncStatus].
  Future<void> runFullBackupIfDue({
    required String masterPath,
    required StorageService storageService,
    bool force = false,
    DateTime? now,
  }) async {
    if (_fullBackupInProgress) return;

    // Constructor login check may still be in flight at startup; verify freshly.
    if (!_isLoggedIn) {
      _isLoggedIn = await _service.isLoggedIn;
    }
    if (!_isLoggedIn) return;

    final currentTime = now ?? DateTime.now();

    if (!force) {
      final settings = await _db.getSettings();
      final lastStr = settings['last_full_backup_time'] as String?;
      final last = lastStr != null ? DateTime.tryParse(lastStr) : null;
      if (last != null && currentTime.difference(last) < fullBackupInterval) {
        return; // Not due yet.
      }
    }

    _fullBackupInProgress = true;
    try {
      await _runFullBackup(masterPath, storageService);
    } catch (e) {
      if (kDebugMode) print('Full backup sweep error: $e');
    } finally {
      _fullBackupInProgress = false;
      // Stamp completion even if some files failed, so a persistently failing
      // file can't force a re-sweep every hour.
      await _db.updateSetting(
        'last_full_backup_time',
        DateTime.now().toIso8601String(),
      );
    }
  }

  Future<void> _runFullBackup(
    String masterPath,
    StorageService storageService,
  ) async {
    final projects = await storageService.listProjects(masterPath);
    for (final project in projects) {
      final projectPath = '$masterPath/$project';
      for (final entry in fullBackupFileMap.entries) {
        try {
          await _backupOneFile(projectPath, project, entry.key, entry.value);
        } catch (e) {
          // Per-file failures must never abort the whole sweep.
          if (kDebugMode) {
            print('Full backup failed for $project/${entry.key}: $e');
          }
        }
      }
    }
  }

  Future<void> _backupOneFile(
    String projectPath,
    String projectName,
    String localFileName,
    String driveFileName,
  ) async {
    final file = File('$projectPath/$localFileName');
    if (!await file.exists()) return; // Skip files that don't exist locally.

    final localMtime = await file.lastModified();
    final driveModified =
        await _service.getLastModified(projectName, driveFileName);

    if (!shouldUploadFile(
      localMtime: localMtime,
      driveModifiedTime: driveModified,
    )) {
      return;
    }

    final content = await file.readAsString();
    // Use the service directly (not syncCurrentFile) so the sweep stays quiet
    // and doesn't flip the edit-sync SyncStatus indicator repeatedly.
    await _service.syncFile(
      projectName: projectName,
      fileName: driveFileName,
      content: content,
    );
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
