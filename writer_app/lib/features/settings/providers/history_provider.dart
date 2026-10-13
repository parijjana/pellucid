// @trace FEAT-20260517-120000-0005
// Description: Provider for tracking writing statistics and session history (Persistent & Visual).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'project_stats.dart';
import 'settings_database.dart';
import '../../editor/providers/storage_service.dart';
import '../../sync/providers/sync_provider.dart';
import '../../sync/models/logical_file.dart';

class DailyStats {
  final String date; // YYYY-MM-DD
  Duration editorTime;
  Duration notesTime;
  int wordCountDelta;

  DailyStats({
    required this.date,
    this.editorTime = Duration.zero,
    this.notesTime = Duration.zero,
    this.wordCountDelta = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'editor_seconds': editorTime.inSeconds,
      'notes_seconds': notesTime.inSeconds,
      'word_count_delta': wordCountDelta,
    };
  }

  factory DailyStats.fromMap(Map<String, dynamic> map) {
    return DailyStats(
      date: map['date'],
      editorTime: Duration(seconds: map['editor_seconds'] ?? 0),
      notesTime: Duration(seconds: map['notes_seconds'] ?? 0),
      wordCountDelta: map['word_count_delta'] ?? 0,
    );
  }
}

class HistoryProvider extends ChangeNotifier with WidgetsBindingObserver {
  final SettingsDatabase _db;
  final StorageService _storageService;
  final SyncProvider? _syncProvider;
  
  List<DailyStats> _history = [];
  DailyStats? _todayStats;
  
  // Project-wide stats (cached from project's stats.json)
  ProjectStats _currentProjectStats = ProjectStats();
  String? _currentProjectPath;
  
  bool _isEditorFocused = false;
  bool _isNotesFocused = false;
  Timer? _metricsTimer;
  int _baseTodayWordCountDelta = 0;

  HistoryProvider({SettingsDatabase? settingsDatabase, StorageService? storageService, SyncProvider? syncProvider})
      : _db = settingsDatabase ?? SettingsDatabase.instance,
        _storageService = storageService ?? StorageService(),
        _syncProvider = syncProvider {
    _loadHistoryFromDB();
    _startMetricsTracker();
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // No binding (plain unit tests): lifecycle flush is simply unavailable.
    }
  }

  bool _observing = false;

  /// How often the in-memory counters are written out while the user keeps
  /// working. Blur, app pause, project switch and dispose flush immediately.
  static const Duration persistInterval = Duration(seconds: 30);

  /// Today's editor time, ticking every second. Listen to this (not the
  /// provider) to show it live, so a tick never rebuilds a whole screen.
  final ValueNotifier<Duration> editorTimeToday = ValueNotifier(Duration.zero);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flushIfDirty();
  }

  List<DailyStats> get history => List.unmodifiable(_history);
  DailyStats? get todayStats => _todayStats;
  ProjectStats get currentProjectStats => _currentProjectStats;

  Future<void> _loadHistoryFromDB() async {
    final maps = await _db.getHistory();
    _history = maps.map((m) => DailyStats.fromMap(m)).toList();
    
    final today = _getTodayKey();
    _todayStats = _history.firstWhere((s) => s.date == today, 
      orElse: () {
        final newToday = DailyStats(date: today);
        _history.insert(0, newToday);
        return newToday;
      });
    editorTimeToday.value = _todayStats!.editorTime;
    notifyListeners();
  }

  String _getTodayKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> loadProjectStats(String? projectPath) async {
    if (_currentProjectPath != null && _currentProjectPath != projectPath) {
      await saveStatsNow(remoteInBackground: true);
    }
    _currentProjectPath = projectPath;
    _initialWordCount = -1;
    _baseTodayWordCountDelta = 0;
    if (projectPath == null) {
      _currentProjectStats = ProjectStats();
    } else {
      _currentProjectStats = await _storageService.readProjectStats(projectPath);
      unawaited(_mergeRemoteStats(projectPath));
    }
    notifyListeners();
  }

  /// Fetches remote stats for [projectPath] (if signed in to Drive) and merges
  /// them in the background if they're ahead of the local values. Runs
  /// un-awaited from [loadProjectStats] so the blocking network round-trip
  /// never delays cold start or a project switch. Guards against the user
  /// having switched to a different project while the fetch was in flight.
  Future<void> _mergeRemoteStats(String projectPath) async {
    if (_syncProvider == null || !_syncProvider.isLoggedIn) return;
    try {
      final normalizedPath = projectPath.replaceAll('\\', '/');
      final projectName = normalizedPath.split('/').last;
      final remoteContent = await _syncProvider.getLatestContent(
        projectName: projectName,
        fileName: LogicalFile.stats,
      );
      // The user may have switched projects while this fetch was in flight;
      // discard stale results rather than clobbering the now-current project.
      if (_currentProjectPath != projectPath) return;
      if (remoteContent != null && remoteContent.trim().isNotEmpty) {
        final remoteJson = jsonDecode(remoteContent);
        final remoteStats = ProjectStats.fromJson(remoteJson);
        if (remoteStats.totalTimeSpent.inSeconds > _currentProjectStats.totalTimeSpent.inSeconds ||
            remoteStats.totalWordCount > _currentProjectStats.totalWordCount) {
          _currentProjectStats = _currentProjectStats.copyWith(
            totalWordCount: remoteStats.totalWordCount > _currentProjectStats.totalWordCount
                ? remoteStats.totalWordCount
                : _currentProjectStats.totalWordCount,
            totalTimeSpent: remoteStats.totalTimeSpent.inSeconds > _currentProjectStats.totalTimeSpent.inSeconds
                ? remoteStats.totalTimeSpent
                : _currentProjectStats.totalTimeSpent,
          );
          await _storageService.saveProjectStats(projectPath, _currentProjectStats);
          if (_currentProjectPath == projectPath) {
            notifyListeners();
          }
        }
      }
    } catch (e) {
      // Silent fallback on connection or parse error
    }
  }

  void setEditorFocus(bool focused) {
    final lost = _isEditorFocused && !focused;
    _isEditorFocused = focused;
    if (lost) _flushIfDirty();
  }

  void setNotesFocus(bool focused) {
    final lost = _isNotesFocused && !focused;
    _isNotesFocused = focused;
    if (lost) _flushIfDirty();
  }

  void _startMetricsTracker() {
    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_todayStats == null) return;

      if (_isEditorFocused || _isNotesFocused) {
        if (_isEditorFocused) {
          _todayStats!.editorTime += const Duration(seconds: 1);
          _currentProjectStats = _currentProjectStats.copyWith(
            totalTimeSpent: _currentProjectStats.totalTimeSpent + const Duration(seconds: 1),
          );
        } else if (_isNotesFocused) {
          _todayStats!.notesTime += const Duration(seconds: 1);
          _currentProjectStats = _currentProjectStats.copyWith(
            totalTimeSpent: _currentProjectStats.totalTimeSpent + const Duration(seconds: 1),
          );
        }
        // A tick only touches memory: no notifyListeners (nothing rebuilds on
        // the clock) and no write; persistence is throttled by _markDirty.
        editorTimeToday.value = _todayStats!.editorTime;
        _markDirty();
      }
    });
  }

  bool _dirty = false;
  Timer? _persistTimer;

  /// Records that memory is ahead of storage and makes sure a write happens
  /// within [persistInterval]. Repeated calls do not postpone that write.
  void _markDirty() {
    _dirty = true;
    _persistTimer ??= Timer(persistInterval, () {
      _persistTimer = null;
      _flushIfDirty();
    });
  }

  void _flushIfDirty() {
    if (!_dirty) return;
    unawaited(saveStatsNow().catchError((_) {}));
  }

  int _initialWordCount = -1;
  void updateWordCount(int count) {
    if (_todayStats == null) return;
    
    if (_initialWordCount == -1) {
      _initialWordCount = count;
      _baseTodayWordCountDelta = _todayStats!.wordCountDelta;
    }
    
    final sessionDelta = count - _initialWordCount;
    _todayStats!.wordCountDelta = _baseTodayWordCountDelta + sessionDelta;
    
    _currentProjectStats = _currentProjectStats.copyWith(totalWordCount: count);
    
    _markDirty();
    notifyListeners();
  }

  /// Sets (or clears, when [goal] is null/non-positive) the current project's
  /// optional word target. Rebuilds explicitly so null truly unsets the goal.
  void setProjectWordGoal(int? goal) {
    _currentProjectStats = ProjectStats(
      totalWordCount: _currentProjectStats.totalWordCount,
      totalTimeSpent: _currentProjectStats.totalTimeSpent,
      wordGoal: (goal != null && goal > 0) ? goal : null,
    );
    _markDirty();
    notifyListeners();
  }

  /// Persists the current project's stats and today's history row.
  ///
  /// With [remoteInBackground] the Drive upload is started but not awaited, so
  /// a project switch never waits on the network (it used to cost one Drive
  /// round-trip here and a second inside [loadProjectStats]). The local files
  /// are always written before this returns.
  Future<void> saveStatsNow({bool remoteInBackground = false}) async {
    _persistTimer?.cancel();
    _persistTimer = null;
    _dirty = false;
    if (_currentProjectPath != null) {
      await _storageService.saveProjectStats(_currentProjectPath!, _currentProjectStats);
      if (_syncProvider != null && _syncProvider.isLoggedIn) {
        try {
          final normalizedPath = _currentProjectPath!.replaceAll('\\', '/');
          final projectName = normalizedPath.split('/').last;
          final statsJson = jsonEncode(_currentProjectStats.toJson());
          final upload = _syncProvider.syncStats(projectName: projectName, statsJson: statsJson);
          if (remoteInBackground) {
            unawaited(upload.catchError((Object _) {}));
          } else {
            await upload;
          }
        } catch (e) {
          // Silent fallback
        }
      }
    }
    if (_todayStats != null) {
      await _db.upsertHistory(
        _todayStats!.date, 
        _todayStats!.editorTime.inSeconds, 
        _todayStats!.notesTime.inSeconds, 
        _todayStats!.wordCountDelta
      );
    }
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    _persistTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _flushIfDirty();
    editorTimeToday.dispose();
    super.dispose();
  }
}
