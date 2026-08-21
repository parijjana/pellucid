import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/google_drive_sync_service.dart';
import '../services/manuscript_migration.dart';
import '../services/project_pull.dart';
import '../models/logical_file.dart';
import '../../settings/providers/settings_database.dart';
import '../../editor/providers/storage_service.dart';
import '../../settings/providers/project_stats.dart';
import '../../sidebar/providers/note_card.dart';

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
    required LogicalFile fileName,
    required String content,
  }) async {
    if (!_isLoggedIn) return;

    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      await _service.syncFile(
        projectName: projectName,
        file: fileName,
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
        file: LogicalFile.notes,
        content: notesJson,
      );
      await refreshLastSynced(projectName, LogicalFile.notes);
    } catch (e) {
      if (kDebugMode) print('Failed to sync notes: $e');
    }
  }

  Future<void> refreshLastSynced(String projectName, LogicalFile fileName) async {
    final driveTime = await _service.getLastModified(projectName, fileName);
    if (driveTime != null) {
      _lastSynced = driveTime.toLocal();
      await _db.updateSetting('last_synced_time', _lastSynced!.toIso8601String());
      notifyListeners();
    }
  }

  Future<void> loadHistory(String projectName, LogicalFile fileName) async {
    if (!_isLoggedIn) return;
    try {
      _history = await _service.getRevisions(projectName, fileName);
      notifyListeners();
    } catch (e) {
      _history = [];
      notifyListeners();
    }
  }

  Future<String> getVersionContent(String revisionId, String projectName, LogicalFile fileName) async {
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
        file: LogicalFile.stats,
        content: statsJson,
      );
      await refreshLastSynced(projectName, LogicalFile.stats);
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

  /// Local filename -> [LogicalFile], matching the editor's Drive schema
  /// exactly so no duplicate files are ever created. `.history/` snapshots
  /// and `categories.json` are intentionally excluded.
  static const Map<String, LogicalFile> fullBackupFileMap = {
    'document.md': LogicalFile.manuscript,
    'notes.json': LogicalFile.notes,
    'stats.json': LogicalFile.stats,
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
    LogicalFile file,
  ) async {
    final localFile = File('$projectPath/$localFileName');
    if (!await localFile.exists()) return; // Skip files that don't exist locally.

    final localMtime = await localFile.lastModified();
    // Freshness is checked against the SAME logical file this method is about
    // to write to below (getLastModified/syncFile both take `file`), so this
    // can never again drift the way it used to when the manuscript's mtime
    // check compared against a Drive file the editor never actually wrote.
    final driveModified = await _service.getLastModified(projectName, file);

    if (!shouldUploadFile(
      localMtime: localMtime,
      driveModifiedTime: driveModified,
    )) {
      return;
    }

    final content = await localFile.readAsString();
    // Use the service directly (not syncCurrentFile) so the sweep stays quiet
    // and doesn't flip the edit-sync SyncStatus indicator repeatedly.
    await _service.syncFile(
      projectName: projectName,
      file: file,
      content: content,
    );
  }

  Future<String?> getLatestContent({
    required String projectName,
    required LogicalFile fileName,
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

  // ---------------------------------------------------------------------------
  // Discovery and pull (Drive -> local).
  //
  // The first read path in the app. Everything above this line is upload-only:
  // nothing enumerated the vault, so a fresh device opened to an empty library
  // while the work sat in Drive. Two rules hold this path safe:
  //
  //   1. A pull NEVER writes into a project this device already has. Local
  //      prose is not overwritten by a remote copy — reconciling a name that
  //      exists on both sides is two-way sync's job (1.2).
  //   2. The manuscript is read from whichever of `manuscript.md` /
  //      `manuscript.md.md` is newer, so this works against a vault the
  //      desktop migration has not swept yet. That is what lets iOS ship
  //      independently of the Mac release train.
  // ---------------------------------------------------------------------------

  /// Every project folder in the vault, paired with whether this device
  /// already has it. Empty when signed out — a signed-out device has nothing
  /// to discover, which is not an error worth surfacing.
  Future<List<RemoteProject>> listRemoteProjects({
    required String masterPath,
    required StorageService storageService,
  }) async {
    if (!_isLoggedIn) {
      _isLoggedIn = await _service.isLoggedIn;
    }
    if (!_isLoggedIn) return [];

    try {
      final remote = await _service.listProjectNames();
      final local = await storageService.listProjects(masterPath);
      return pairWithLocalProjects(remoteNames: remote, localNames: local);
    } catch (e) {
      if (kDebugMode) print('Failed to list remote projects: $e');
      return [];
    }
  }

  /// Copies one project from the vault into the local master directory.
  ///
  /// Refuses if the project already exists locally. The manuscript is
  /// required; notes and stats are best-effort, and a file that fails to
  /// parse is skipped rather than written as garbage — writing an unparseable
  /// `notes.json` locally would just trip the read-failure latch later and
  /// lock the project's notes for no reason.
  Future<PullResult> pullProject({
    required String projectName,
    required String masterPath,
    required StorageService storageService,
  }) async {
    if (!_isLoggedIn) {
      _isLoggedIn = await _service.isLoggedIn;
    }
    if (!_isLoggedIn) {
      return PullResult(projectName: projectName, outcome: PullOutcome.notLoggedIn);
    }

    try {
      final local = await storageService.listProjects(masterPath);
      if (local.any((n) => n.toLowerCase() == projectName.toLowerCase())) {
        return PullResult(
          projectName: projectName,
          outcome: PullOutcome.alreadyExistsLocally,
        );
      }

      final canonical = await _service.findRawFileInProject(
        projectName,
        canonicalManuscriptDriveFileName,
      );
      final legacy = await _service.findRawFileInProject(
        projectName,
        legacyManuscriptDriveFileName,
      );

      final source = chooseManuscriptSource(
        canonicalExists: canonical != null,
        legacyExists: legacy != null,
        canonicalModifiedTime: canonical?.modifiedTime,
        legacyModifiedTime: legacy?.modifiedTime,
      );

      switch (source) {
        case ManuscriptSource.none:
          return PullResult(
            projectName: projectName,
            outcome: PullOutcome.noManuscript,
          );
        case ManuscriptSource.ambiguous:
          return PullResult(
            projectName: projectName,
            outcome: PullOutcome.ambiguousManuscript,
          );
        case ManuscriptSource.canonical:
        case ManuscriptSource.legacy:
          break;
      }

      final chosen = source == ManuscriptSource.legacy ? legacy! : canonical!;
      final manuscript = await _service.downloadFileContent(chosen.id!);
      if (manuscript == null) {
        return PullResult(
          projectName: projectName,
          outcome: PullOutcome.noManuscript,
        );
      }

      // Nothing is written to disk until the manuscript is in hand, so a
      // failed download cannot leave an empty project behind.
      await storageService.initProject(masterPath, projectName);
      final projectPath = '$masterPath/$projectName';
      await storageService.saveDocument(projectPath, manuscript);

      final pulled = <LogicalFile>{LogicalFile.manuscript};
      final skipped = <LogicalFile>{};

      final notesJson = await _service.downloadProjectFile(projectName, LogicalFile.notes);
      if (notesJson != null) {
        try {
          final cards = (jsonDecode(notesJson) as List<dynamic>)
              .map((j) => NoteCard.fromJson(j))
              .toList();
          await storageService.saveNotes(projectPath, cards);
          pulled.add(LogicalFile.notes);
        } catch (e) {
          skipped.add(LogicalFile.notes);
        }
      }

      final statsJson = await _service.downloadProjectFile(projectName, LogicalFile.stats);
      if (statsJson != null) {
        try {
          await storageService.saveProjectStats(
            projectPath,
            ProjectStats.fromJson(jsonDecode(statsJson)),
          );
          pulled.add(LogicalFile.stats);
        } catch (e) {
          skipped.add(LogicalFile.stats);
        }
      }

      return PullResult(
        projectName: projectName,
        outcome: PullOutcome.pulled,
        filesPulled: pulled,
        filesSkipped: skipped,
      );
    } catch (e) {
      if (kDebugMode) print('Pull failed for "$projectName": $e');
      return PullResult(
        projectName: projectName,
        outcome: PullOutcome.failed,
        error: e,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // One-time, data-preserving manuscript filename migration
  // (docs/two-way-sync-design.md §1). Repairs Drive-side divergence between
  // `manuscript.md` and the legacy `manuscript.md.md` left behind by the
  // filename bug this LogicalFile refactor fixes. Drive-side only: never
  // touches, deletes, or overwrites anything on local disk. Never deletes
  // `manuscript.md.md`. See manuscript_migration.dart for the pure decision
  // logic and its idempotency argument.
  // ---------------------------------------------------------------------------

  bool _manuscriptMigrationInProgress = false;
  bool get isManuscriptMigrationInProgress => _manuscriptMigrationInProgress;

  /// Sweeps every project in the vault and reconciles the manuscript filename
  /// divergence. Safe to call repeatedly and safe to interrupt at any point:
  /// - Already-migrated projects are skipped via a persisted marker
  ///   ([SettingsDatabase.getMigratedManuscriptProjects]), so a fully migrated
  ///   vault does one cheap `files.list` per app start and nothing else.
  /// - If the app is killed mid-sweep, unmarked projects simply get
  ///   re-evaluated on the next run. Re-evaluating an already-correct project
  ///   is a no-op (see [decideManuscriptMigration]'s idempotency argument), so
  ///   there is no unsafe partial state to recover from.
  /// - A single project's failure or ambiguity never aborts the sweep for
  ///   other projects — it's logged and left unmarked so it will be retried.
  Future<void> runManuscriptMigrationIfNeeded() async {
    if (_manuscriptMigrationInProgress) return;

    if (!_isLoggedIn) {
      _isLoggedIn = await _service.isLoggedIn;
    }
    if (!_isLoggedIn) return;

    _manuscriptMigrationInProgress = true;
    try {
      final projectNames = await _service.listProjectNames();
      final alreadyMigrated = await _db.getMigratedManuscriptProjects();

      for (final projectName in projectNames) {
        if (alreadyMigrated.contains(projectName)) continue;
        try {
          await _migrateOneProjectManuscript(projectName);
          await _db.markManuscriptMigrated(projectName);
        } catch (e) {
          // Never guess, never let one project's ambiguity or error touch
          // any other project. Left unmarked so it is retried next time.
          if (kDebugMode) {
            print('Manuscript migration aborted for project "$projectName": $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Manuscript migration sweep error: $e');
    } finally {
      _manuscriptMigrationInProgress = false;
    }
  }

  Future<void> _migrateOneProjectManuscript(String projectName) async {
    final canonical = await _service.findRawFileInProject(
      projectName,
      canonicalManuscriptDriveFileName,
    );
    final legacy = await _service.findRawFileInProject(
      projectName,
      legacyManuscriptDriveFileName,
    );

    final decision = decideManuscriptMigration(
      canonicalExists: canonical != null,
      legacyExists: legacy != null,
      canonicalModifiedTime: canonical?.modifiedTime,
      legacyModifiedTime: legacy?.modifiedTime,
    );

    if (decision.isAbort) {
      throw StateError(
        'Ambiguous migration state for "$projectName": both $canonicalManuscriptDriveFileName '
        'and $legacyManuscriptDriveFileName exist but a modifiedTime could not be read for '
        'one of them. Refusing to guess a winner.',
      );
    }

    if (!decision.shouldCopyLegacyToCanonical) return; // Nothing to do; will be marked done.

    // legacy is guaranteed non-null here: both onlyLegacyExists and
    // legacyIsNewer require legacyExists == true.
    final legacyContent = await _service.downloadFileContent(legacy!.id!);
    if (legacyContent == null) {
      throw StateError('Could not download legacy manuscript content for "$projectName".');
    }

    if (canonical != null) {
      // Update the EXISTING canonical file (never delete-then-create). Drive
      // retains the prior revision automatically on update, so whatever
      // manuscript.md held immediately before this call remains recoverable
      // via Drive's revision history.
      await _service.overwriteFileContent(canonical.id!, legacyContent);
    } else {
      await _service.createRawFileInProject(
        projectName,
        canonicalManuscriptDriveFileName,
        legacyContent,
      );
    }

    // legacy (manuscript.md.md) is NEVER deleted or modified. It — and its
    // own revision history — is left in place permanently as a safety copy.
  }
}
