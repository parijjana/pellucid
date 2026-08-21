// @trace FEAT-20260516-120000-0001
// Description: Provider for managing editor state and auto-saving (Updated for Multi-Project).

import 'dart:async';
import 'package:flutter/material.dart';
import 'storage_service.dart';
import '../../settings/providers/settings_database.dart';

import '../../sync/providers/sync_provider.dart';
import '../../sync/models/logical_file.dart';
import '../../sidebar/providers/note_card.dart';

class EditorProvider extends ChangeNotifier {
  final StorageService _storageService;
  final SettingsDatabase _db;
  
  String _content = StorageService.userManualContent;
  String? _currentProjectPath;
  double _zoomLevel = 1.0;
  double _pageWidth = 800.0;
  double _horizontalPosition = 0.5;
  Timer? _debounceTimer;

  // Cloud Sync Rate Limiting
  Timer? _syncDebounceTimer;
  Timer? _syncThrottleTimer;
  bool _hasUnsyncedChanges = false;

  // Configurable durations for TDD testing (default to 30 minutes)
  Duration syncDebounceDuration = const Duration(minutes: 30);
  Duration syncThrottleDuration = const Duration(minutes: 30);

  // Read-failure latch. When the last load of `document.md` THREW, the real
  // content on disk is unknown, so every write path is disabled until a
  // successful reload. Without this, a failed read shows a blank page and the
  // 2-second autosave writes that blank over the manuscript.
  bool _documentLoadFailed = false;
  Object? _loadError;

  // Mirror latch. A project pulled out of the Drive vault is owned by another
  // device, so this one does not write to it: the first edit forks it into a
  // project this device owns (docs/release-plan.md, "iOS 1.0 sync model").
  // Until the fork lands, nothing is saved or synced for the mirror.
  bool _isMirrorProject = false;
  bool _forkRequested = false;

  /// Resolves whether a project path is a mirror. Injected once at startup so
  /// that every `loadProject` call site gets the rule for free — there are
  /// eleven of them across the app, and one that forgot would silently make a
  /// mirror writable again.
  bool Function(String projectPath)? isMirrorProjectPath;

  /// Called once, on the first edit of a mirrored project, with the editor's
  /// live text so a new fork can carry the keystroke that triggered it. The
  /// screen owns the fork itself — creating projects and switching the app to
  /// them is not this provider's job.
  Future<void> Function(String content)? onMirrorEditAttempt;

  // Local Snapshot Safety Net: rolling on-disk snapshots independent of cloud sync
  DateTime? _lastSnapshotTime;
  Duration snapshotInterval = const Duration(minutes: 10);

  EditorProvider({StorageService? storageService, SettingsDatabase? settingsDatabase}) 
      : _storageService = storageService ?? StorageService(),
        _db = settingsDatabase ?? SettingsDatabase.instance;

  String get content => _content;
  double get zoomLevel => _zoomLevel;
  double get pageWidth => _pageWidth;
  double get horizontalPosition => _horizontalPosition;
  bool get hasUnsyncedChanges => _hasUnsyncedChanges;

  /// True when the last load of this project's document threw. The editor is
  /// read-only and nothing is saved or synced while this holds.
  bool get documentLoadFailed => _documentLoadFailed;

  /// The exception behind [documentLoadFailed], for display. Null otherwise.
  Object? get loadError => _loadError;

  /// True when the open project mirrors one owned by another device. The
  /// editor accepts typing — that is what triggers the fork — but nothing is
  /// written to the mirror itself.
  bool get isMirrorProject => _isMirrorProject;

  Future<void> loadSettings() async {
    final settings = await _db.getSettings();
    _zoomLevel = settings['zoom_level'] ?? 1.0;
    _pageWidth = settings['page_width'] ?? 800.0;
    _horizontalPosition = settings['horizontal_position'] ?? 0.5;
    notifyListeners();
  }

  void setZoomLevel(double level) {
    if (_zoomLevel == level) return;
    _zoomLevel = level.clamp(0.5, 2.0);
    _db.updateSetting('zoom_level', _zoomLevel);
    notifyListeners();
  }

  void zoomIn() => setZoomLevel(_zoomLevel + 0.1);
  void zoomOut() => setZoomLevel(_zoomLevel - 0.1);

  void setPageWidth(double width) {
    _pageWidth = width.clamp(400.0, 2000.0);
    _db.updateSetting('page_width', _pageWidth);
    notifyListeners();
  }

  void setHorizontalPosition(double pos) {
    _horizontalPosition = pos.clamp(0.0, 1.0);
    _db.updateSetting('horizontal_position', _horizontalPosition);
    notifyListeners();
  }

  Future<void> loadProject(String? projectPath, {bool isMirror = false}) async {
    _debounceTimer?.cancel();
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = null;
    _syncThrottleTimer?.cancel();
    _syncThrottleTimer = null;

    // Never snapshot content we did not successfully read — that writes a
    // blank into `.history/`, which is the very backstop this protects.
    if (_currentProjectPath != null &&
        _content.isNotEmpty &&
        !_documentLoadFailed &&
        !_isMirrorProject) {
      await _storageService.saveLocalSnapshot(_currentProjectPath!, _content);
    }
    _lastSnapshotTime = null;

    _currentProjectPath = projectPath;
    // Defaults to false, so a call site that forgets to pass this makes a
    // mirror editable rather than making an owned project unwritable. The
    // cost of that mistake is divergence from Drive; the cost of the reverse
    // would be a writer who cannot type.
    _isMirrorProject = isMirror ||
        (projectPath != null &&
            (isMirrorProjectPath?.call(projectPath) ?? false));
    _forkRequested = false;
    if (projectPath == null) {
      _content = StorageService.userManualContent;
      _documentLoadFailed = false;
      _loadError = null;
    } else {
      final read = await _storageService.readDocument(projectPath);
      _content = read.value;
      _documentLoadFailed = read.failed;
      _loadError = read.error;
    }
    _hasUnsyncedChanges = false;
    notifyListeners();
  }

  /// Re-attempts a load that failed, so a transient error (an undownloaded
  /// cloud placeholder, a locked file) can be cleared without restarting.
  Future<void> retryLoad() async {
    if (!_documentLoadFailed || _currentProjectPath == null) return;
    final read = await _storageService.readDocument(_currentProjectPath!);
    _content = read.value;
    _documentLoadFailed = read.failed;
    _loadError = read.error;
    notifyListeners();
  }

  void updateContent(String newContent, {SyncProvider? syncProvider, String? projectName, Duration? syncInterval}) {
    if (_content == newContent) return;
    _content = newContent;

    if (_isMirrorProject) {
      // The edit is kept on screen and handed to the fork, but never written
      // to the mirror. Fired once: the fork is async and a fast typist
      // produces several more keystrokes before it lands.
      if (!_forkRequested) {
        _forkRequested = true;
        onMirrorEditAttempt?.call(newContent);
      }
      notifyListeners();
      return;
    }

    _autoSave(syncProvider: syncProvider, projectName: projectName, syncInterval: syncInterval);
    notifyListeners();
  }

  void _autoSave({SyncProvider? syncProvider, String? projectName, Duration? syncInterval}) {
    if (_currentProjectPath == null) return;
    // The document on disk is unknown after a failed read. Saving now would
    // overwrite it with whatever the blank editor happens to hold.
    if (_documentLoadFailed) return;
    // A mirror is another device's project. Nothing here writes to it.
    if (_isMirrorProject) return;

    // 1. Local Auto-Save (2s debounce)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      await _storageService.saveDocument(_currentProjectPath!, _content);
      _maybeTakeLocalSnapshot();
    });

    // 2. Cloud Sync (Rate limited)
    if (syncProvider != null && projectName != null) {
      _hasUnsyncedChanges = true;
      final debounceDuration = syncInterval ?? syncDebounceDuration;
      final throttleDuration = syncInterval ?? syncThrottleDuration;

      // Debounce Timer (fires after idle duration)
      _syncDebounceTimer?.cancel();
      _syncDebounceTimer = Timer(debounceDuration, () async {
        await _performSync(syncProvider, projectName);
      });

      // Throttle Timer (forces sync during continuous typing)
      _syncThrottleTimer ??= Timer(throttleDuration, () async {
        await _performSync(syncProvider, projectName);
      });
    }
  }

  void _maybeTakeLocalSnapshot() {
    if (_currentProjectPath == null || _content.isEmpty || _documentLoadFailed) return;
    final now = DateTime.now();
    if (_lastSnapshotTime != null && now.difference(_lastSnapshotTime!) < snapshotInterval) return;
    _lastSnapshotTime = now;
    _storageService.saveLocalSnapshot(_currentProjectPath!, _content);
  }

  Future<void> _performSync(SyncProvider syncProvider, String projectName) async {
    if (!_hasUnsyncedChanges) return;
    // Belt and braces: pushing an unread document to Drive would put the blank
    // into cloud version history too, where it outlives the local file.
    if (_documentLoadFailed) return;

    // Cancel both timers to prevent duplicate/redundant runs
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = null;
    _syncThrottleTimer?.cancel();
    _syncThrottleTimer = null;

    await syncProvider.syncCurrentFile(
      projectName: projectName,
      fileName: LogicalFile.manuscript,
      content: _content,
    );

    if (syncProvider.status == SyncStatus.success) {
      _hasUnsyncedChanges = false;
    }
  }

  Future<void> flushSync({SyncProvider? syncProvider, String? projectName}) async {
    if (_hasUnsyncedChanges && syncProvider != null && projectName != null) {
      await _performSync(syncProvider, projectName);
    }
  }

  void syncAttributions(NoteCard? attributionCard, {SyncProvider? syncProvider, String? projectName}) {
    if (attributionCard == null) {
      final newContent = _removeAttributionsFromMarkdown(_content);
      if (newContent != _content) {
        _content = newContent;
        _autoSave(syncProvider: syncProvider, projectName: projectName);
        notifyListeners();
      }
    } else {
      final listMarkdown = attributionCard.getAttributionMarkdown();
      final newContent = _syncAttributionsInMarkdown(_content, listMarkdown);
      if (newContent != _content) {
        _content = newContent;
        _autoSave(syncProvider: syncProvider, projectName: projectName);
        notifyListeners();
      }
    }
  }

  String _syncAttributionsInMarkdown(String originalMarkdown, String attributionsListMarkdown) {
    final lines = originalMarkdown.split('\n');
    int startIndex = -1;
    int endIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (RegExp(r'^#\s+Attributions$', caseSensitive: false).hasMatch(trimmed)) {
        startIndex = i;
        break;
      }
    }

    final endsWithNewLine = originalMarkdown.endsWith('\n');

    if (startIndex != -1) {
      for (int i = startIndex + 1; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('# ')) {
          endIndex = i;
          break;
        }
      }

      final before = lines.sublist(0, startIndex);
      final after = endIndex != -1 ? lines.sublist(endIndex) : <String>[];

      while (before.isNotEmpty && before.last.trim().isEmpty) {
        before.removeLast();
      }
      while (after.isNotEmpty && after.first.trim().isEmpty) {
        after.removeAt(0);
      }

      final newSection = [
        if (before.isNotEmpty) '',
        '# Attributions',
        '',
        attributionsListMarkdown.trim(),
        if (after.isNotEmpty) '',
      ];

      final result = [...before, ...newSection, ...after].join('\n');
      return (endsWithNewLine || after.isEmpty) && !result.endsWith('\n') ? '$result\n' : result;
    } else {
      final buffer = StringBuffer(originalMarkdown);
      if (originalMarkdown.isNotEmpty && !originalMarkdown.endsWith('\n')) {
        buffer.write('\n');
      }
      if (originalMarkdown.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write('# Attributions\n\n');
      buffer.write(attributionsListMarkdown.trim());
      buffer.write('\n');
      return buffer.toString();
    }
  }

  String _removeAttributionsFromMarkdown(String originalMarkdown) {
    final lines = originalMarkdown.split('\n');
    int startIndex = -1;
    int endIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (RegExp(r'^#\s+Attributions$', caseSensitive: false).hasMatch(trimmed)) {
        startIndex = i;
        break;
      }
    }

    if (startIndex != -1) {
      for (int i = startIndex + 1; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('# ')) {
          endIndex = i;
          break;
        }
      }

      final before = lines.sublist(0, startIndex);
      while (before.isNotEmpty && before.last.trim().isEmpty) {
        before.removeLast();
      }
      final after = endIndex != -1 ? lines.sublist(endIndex) : <String>[];
      while (after.isNotEmpty && after.first.trim().isEmpty) {
        after.removeAt(0);
      }

      final spacer = (before.isNotEmpty && after.isNotEmpty) ? [''] : [];
      final endsWithNewLine = originalMarkdown.endsWith('\n');
      final result = [...before, ...spacer, ...after].join('\n');
      return endsWithNewLine && !result.endsWith('\n') ? '$result\n' : result;
    }
    return originalMarkdown;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _syncDebounceTimer?.cancel();
    _syncThrottleTimer?.cancel();
    super.dispose();
  }
}
