// @trace FEAT-20260516-120000-0001
// Description: Provider for managing editor state and auto-saving (Updated for Multi-Project).

import 'dart:async';
import 'package:flutter/material.dart';
import 'storage_service.dart';
import '../../settings/providers/settings_database.dart';

import '../../sync/providers/sync_provider.dart';
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

  // Configurable durations for TDD testing (default to 15 minutes)
  Duration syncDebounceDuration = const Duration(minutes: 15);
  Duration syncThrottleDuration = const Duration(minutes: 15);

  EditorProvider({StorageService? storageService, SettingsDatabase? settingsDatabase}) 
      : _storageService = storageService ?? StorageService(),
        _db = settingsDatabase ?? SettingsDatabase.instance;

  String get content => _content;
  double get zoomLevel => _zoomLevel;
  double get pageWidth => _pageWidth;
  double get horizontalPosition => _horizontalPosition;
  bool get hasUnsyncedChanges => _hasUnsyncedChanges;

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

  Future<void> loadProject(String? projectPath) async {
    _debounceTimer?.cancel();
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = null;
    _syncThrottleTimer?.cancel();
    _syncThrottleTimer = null;

    _currentProjectPath = projectPath;
    if (projectPath == null) {
      _content = StorageService.userManualContent;
    } else {
      _content = await _storageService.readDocument(projectPath);
    }
    _hasUnsyncedChanges = false;
    notifyListeners();
  }

  void updateContent(String newContent, {SyncProvider? syncProvider, String? projectName}) {
    if (_content == newContent) return;
    _content = newContent;
    _autoSave(syncProvider: syncProvider, projectName: projectName);
    notifyListeners();
  }

  void _autoSave({SyncProvider? syncProvider, String? projectName}) {
    if (_currentProjectPath == null) return;

    // 1. Local Auto-Save (2s debounce)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      await _storageService.saveDocument(_currentProjectPath!, _content);
    });

    // 2. Cloud Sync (Rate limited)
    if (syncProvider != null && projectName != null) {
      _hasUnsyncedChanges = true;

      // Debounce Timer (fires after idle duration)
      _syncDebounceTimer?.cancel();
      _syncDebounceTimer = Timer(syncDebounceDuration, () async {
        await _performSync(syncProvider, projectName);
      });

      // Throttle Timer (forces sync during continuous typing)
      _syncThrottleTimer ??= Timer(syncThrottleDuration, () async {
        await _performSync(syncProvider, projectName);
      });
    }
  }

  Future<void> _performSync(SyncProvider syncProvider, String projectName) async {
    if (!_hasUnsyncedChanges) return;

    // Cancel both timers to prevent duplicate/redundant runs
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = null;
    _syncThrottleTimer?.cancel();
    _syncThrottleTimer = null;

    await syncProvider.syncCurrentFile(
      projectName: projectName,
      fileName: 'manuscript.md',
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
