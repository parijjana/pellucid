// @trace FEAT-20260517-115000-0004
// Description: Provider for application settings, including multi-project state and cached metrics.

import 'dart:async';
import 'package:flutter/material.dart';
import 'settings_database.dart';
import 'project_stats.dart';
import '../../editor/providers/storage_service.dart';

class ProjectInfo {
  final String name;
  final ProjectStats stats;

  ProjectInfo({required this.name, required this.stats});
}

class SettingsProvider extends ChangeNotifier {
  final SettingsDatabase _db;
  final StorageService _storageService;

  // Clock Settings
  bool _clockEnabled = false;

  // Session Timer Settings
  bool _currentSessionEnabled = false;
  bool _targetSessionEnabled = false;
  Duration _targetSessionTime = const Duration(minutes: 60);
  Duration _currentSessionTime = Duration.zero;
  Timer? _sessionTimer;

  // Focus/Pomodoro Settings
  bool _focusTimerEnabled = false;
  final Duration _pomodoroDuration = const Duration(minutes: 25);
  Duration _pomodoroRemaining = const Duration(minutes: 25);
  bool _isPomodoroActive = false;
  Timer? _pomodoroTimer;

  // Alarm Settings
  DateTime? _alarmTime;
  bool _isAlarmTriggered = false;

  // Window Focus
  bool _isWindowFocused = true;

  // Battery Settings
  bool _batteryGuardEnabled = true;
  int _batteryAlertThreshold = 20;
  bool _showBatteryPercentage = true;

  // Notes Dialog Settings
  bool _lastNotesFullscreenState = false;

  // Project Settings
  String? _masterDirectoryPath;
  String? _currentProjectName;
  List<ProjectInfo> _availableProjects = [];

  SettingsProvider({SettingsDatabase? settingsDatabase, StorageService? storageService}) 
      : _db = settingsDatabase ?? SettingsDatabase.instance,
        _storageService = storageService ?? StorageService() {
    _startSessionTracker();
    _startAlarmChecker();
  }

  Future<void> loadSettings() async {
    final settings = await _db.getSettings();
    _clockEnabled = settings['clock_enabled'] == 1;
    _currentSessionEnabled = settings['current_session_enabled'] == 1;
    _targetSessionEnabled = settings['target_session_enabled'] == 1;
    _focusTimerEnabled = settings['focus_timer_enabled'] == 1;
    _batteryGuardEnabled = (settings['battery_guard_enabled'] ?? 1) == 1;
    _batteryAlertThreshold = settings['battery_alert_threshold'] ?? 20;
    _showBatteryPercentage = (settings['show_battery_percentage'] ?? 1) == 1;
    _lastNotesFullscreenState = (settings['last_notes_fullscreen_state'] ?? 0) == 1;
    _masterDirectoryPath = settings['master_directory_path'];
    _currentProjectName = settings['current_project_name'];
    
    if (_masterDirectoryPath != null) {
      // Ensure User Manual always exists in the master directory
      await _storageService.initProject(
        _masterDirectoryPath!, 
        'User Manual', 
        initialContent: StorageService.userManualContent
      );
      
      await refreshProjects();
      
      // Default to User Manual if nothing is selected
      if (_currentProjectName == null) {
        await setCurrentProject('User Manual');
      }
    }
    notifyListeners();
  }

  // Getters
  bool get clockEnabled => _clockEnabled;
  bool get currentSessionEnabled => _currentSessionEnabled;
  bool get targetSessionEnabled => _targetSessionEnabled;
  Duration get targetSessionTime => _targetSessionTime;
  Duration get currentSessionTime => _currentSessionTime;
  bool get focusTimerEnabled => _focusTimerEnabled;
  Duration get pomodoroRemaining => _pomodoroRemaining;
  bool get isPomodoroActive => _isPomodoroActive;
  DateTime? get alarmTime => _alarmTime;
  bool get isAlarmTriggered => _isAlarmTriggered;
  String? get masterDirectoryPath => _masterDirectoryPath;
  String? get currentProjectName => _currentProjectName;
  List<ProjectInfo> get availableProjects => _availableProjects;
  bool get isWindowFocused => _isWindowFocused;
  bool get batteryGuardEnabled => _batteryGuardEnabled;
  int get batteryAlertThreshold => _batteryAlertThreshold;
  bool get showBatteryPercentage => _showBatteryPercentage;
  bool get lastNotesFullscreenState => _lastNotesFullscreenState;

  String? get currentProjectPath {
    if (_masterDirectoryPath == null || _currentProjectName == null) return null;
    return '$_masterDirectoryPath/$_currentProjectName';
  }

  // Setters
  void setWindowFocused(bool focused) {
    if (_isWindowFocused == focused) return;
    _isWindowFocused = focused;
    notifyListeners();
  }

  void toggleClock(bool enabled) {
    _clockEnabled = enabled;
    _db.updateSetting('clock_enabled', enabled);
    notifyListeners();
  }

  void toggleCurrentSession(bool enabled) {
    _currentSessionEnabled = enabled;
    _db.updateSetting('current_session_enabled', enabled);
    if (!enabled) toggleTargetSession(false);
    notifyListeners();
  }

  void toggleTargetSession(bool enabled) {
    _targetSessionEnabled = enabled;
    _db.updateSetting('target_session_enabled', enabled);
    notifyListeners();
  }

  void toggleBatteryGuard(bool enabled) {
    _batteryGuardEnabled = enabled;
    _db.updateSetting('battery_guard_enabled', enabled);
    notifyListeners();
  }

  void setBatteryAlertThreshold(int threshold) {
    _batteryAlertThreshold = threshold.clamp(5, 100);
    _db.updateSetting('battery_alert_threshold', _batteryAlertThreshold);
    notifyListeners();
  }

  void toggleShowBatteryPercentage(bool enabled) {
    _showBatteryPercentage = enabled;
    _db.updateSetting('show_battery_percentage', enabled);
    notifyListeners();
  }

  void setLastNotesFullscreenState(bool isFullscreen) {
    _lastNotesFullscreenState = isFullscreen;
    _db.updateSetting('last_notes_fullscreen_state', isFullscreen);
    notifyListeners();
  }

  Future<void> setMasterDirectory(String? path) async {
    _masterDirectoryPath = path;
    _db.updateSetting('master_directory_path', path);
    if (path != null) {
      // Auto-seed User Manual
      await _storageService.initProject(
        path, 
        'User Manual', 
        initialContent: StorageService.userManualContent
      );
      await refreshProjects();
      
      // If no project is selected, default to User Manual
      if (_currentProjectName == null) {
        await setCurrentProject('User Manual');
      }
    }
    notifyListeners();
  }

  Future<void> refreshProjects() async {
    if (_masterDirectoryPath == null) return;
    final List<String> folderNames = await _storageService.listProjects(_masterDirectoryPath!);
    
    final List<ProjectInfo> projects = [];
    for (var name in folderNames) {
      final stats = await _storageService.readProjectStats('$_masterDirectoryPath/$name');
      projects.add(ProjectInfo(name: name, stats: stats));
    }
    
    _availableProjects = projects;
    notifyListeners();
  }

  Future<void> createProject(String name) async {
    if (_masterDirectoryPath == null) return;
    await _storageService.initProject(_masterDirectoryPath!, name);
    await refreshProjects();
    await setCurrentProject(name);
  }

  Future<void> setCurrentProject(String? name) async {
    _currentProjectName = name;
    await _db.updateSetting('current_project_name', name);
    notifyListeners();
  }

  void dismissAlarm() {
    _isAlarmTriggered = false;
    _alarmTime = null;
    notifyListeners();
  }

  void setAlarm(DateTime time) {
    _alarmTime = time;
    _isAlarmTriggered = false;
    notifyListeners();
  }

  void clearAlarm() {
    _alarmTime = null;
    _isAlarmTriggered = false;
    notifyListeners();
  }

  void _startAlarmChecker() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_alarmTime != null && !_isAlarmTriggered) {
        final now = DateTime.now();
        if (now.isAfter(_alarmTime!) || now.isAtSameMomentAs(_alarmTime!)) {
          _isAlarmTriggered = true;
          notifyListeners();
        }
      }
    });
  }

  void toggleFocusTimer(bool enabled) {
    _focusTimerEnabled = enabled;
    _db.updateSetting('focus_timer_enabled', enabled);
    if (!enabled) pausePomodoro();
    notifyListeners();
  }

  // Pomodoro Logic
  void startPomodoro() {
    if (_isPomodoroActive) return;
    _isPomodoroActive = true;
    _pomodoroTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isWindowFocused) return;
      if (_pomodoroRemaining.inSeconds > 0) {
        _pomodoroRemaining -= const Duration(seconds: 1);
      } else {
        _isPomodoroActive = false;
        timer.cancel();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void pausePomodoro() {
    _isPomodoroActive = false;
    _pomodoroTimer?.cancel();
    notifyListeners();
  }

  void resetPomodoro() {
    pausePomodoro();
    _pomodoroRemaining = _pomodoroDuration;
    notifyListeners();
  }

  void setTargetSessionTime(Duration duration) {
    _targetSessionTime = duration;
    notifyListeners();
  }

  void _startSessionTracker() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isWindowFocused) return;
      _currentSessionTime += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _pomodoroTimer?.cancel();
    super.dispose();
  }
}
