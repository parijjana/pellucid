// @trace FEAT-20260517-120000-0005
// Description: Provider for tracking writing statistics and session history (Persistent & Visual).

import 'dart:async';
import 'package:flutter/material.dart';
import 'project_stats.dart';
import 'settings_database.dart';
import '../../editor/providers/storage_service.dart';

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

class HistoryProvider extends ChangeNotifier {
  final SettingsDatabase _db = SettingsDatabase.instance;
  final StorageService _storageService = StorageService();
  
  List<DailyStats> _history = [];
  DailyStats? _todayStats;
  
  // Project-wide stats (cached from project's stats.json)
  ProjectStats _currentProjectStats = ProjectStats();
  String? _currentProjectPath;
  
  bool _isEditorFocused = false;
  bool _isNotesFocused = false;
  Timer? _metricsTimer;

  HistoryProvider() {
    _loadHistoryFromDB();
    _startMetricsTracker();
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
    notifyListeners();
  }

  String _getTodayKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> loadProjectStats(String? projectPath) async {
    _currentProjectPath = projectPath;
    if (projectPath == null) {
      _currentProjectStats = ProjectStats();
    } else {
      _currentProjectStats = await _storageService.readProjectStats(projectPath);
    }
    notifyListeners();
  }

  void setEditorFocus(bool focused) {
    _isEditorFocused = focused;
  }

  void setNotesFocus(bool focused) {
    _isNotesFocused = focused;
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
        _autoSaveToDB();
        _autoSaveProjectStats();
        notifyListeners();
      }
    });
  }

  Timer? _dbDebouncer;
  void _autoSaveToDB() {
    _dbDebouncer?.cancel();
    _dbDebouncer = Timer(const Duration(seconds: 10), () {
      if (_todayStats != null) {
        _db.upsertHistory(
          _todayStats!.date, 
          _todayStats!.editorTime.inSeconds, 
          _todayStats!.notesTime.inSeconds, 
          _todayStats!.wordCountDelta
        );
      }
    });
  }

  Timer? _statsDebouncer;
  void _autoSaveProjectStats() {
    if (_currentProjectPath == null) return;
    _statsDebouncer?.cancel();
    _statsDebouncer = Timer(const Duration(seconds: 5), () {
      _storageService.saveProjectStats(_currentProjectPath!, _currentProjectStats);
    });
  }

  int _initialWordCount = -1;
  void updateWordCount(int count) {
    if (_todayStats == null) return;
    
    if (_initialWordCount == -1) {
      _initialWordCount = count;
    }
    
    final delta = count - _initialWordCount;
    _todayStats!.wordCountDelta = delta;
    
    _currentProjectStats = _currentProjectStats.copyWith(totalWordCount: count);
    
    _autoSaveToDB();
    _autoSaveProjectStats();
    notifyListeners();
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    _dbDebouncer?.cancel();
    _statsDebouncer?.cancel();
    super.dispose();
  }
}
