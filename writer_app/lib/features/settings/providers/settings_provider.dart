// @trace FEAT-20260517-115000-0004
// Description: Provider for application settings, including multi-project state and cached metrics.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file/memory.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'settings_database.dart';
import 'project_stats.dart';
import '../../editor/providers/storage_service.dart';
import '../../sidebar/providers/note_card.dart';
import '../../sync/services/project_fork.dart';

class ProjectInfo {
  final String name;
  final ProjectStats stats;

  ProjectInfo({required this.name, required this.stats});
}

class SettingsProvider extends ChangeNotifier {
  final SettingsDatabase _db;
  final StorageService _storageService;

  // macOS security-scoped bookmarks: under the App Sandbox a raw path grants no
  // access after relaunch, so we persist a bookmark for the master folder and
  // resolve it on load. Stateless singleton; only invoked on macOS.
  final SecureBookmarks _bookmarks = SecureBookmarks();

  // Projects that arrived here by being pulled out of the Drive vault. Another
  // device owns them, so the first edit forks rather than writing in place.
  // See SettingsDatabase.getMirroredProjects for why absence means "ours".
  Set<String> _mirroredProjects = {};

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

  // Editor Focus Settings
  bool _typewriterEnabled = false;
  bool _paragraphFocusEnabled = false;
  bool _codexLinkingEnabled = false;

  // TOC Settings
  bool _tocWordCountsEnabled = true;

  // Daily Writing Goal (words per day; 0 = off/unset)
  int _dailyWordGoal = 0;

  // Spell Check Setting
  bool _spellCheckEnabled = true;

  // Google OAuth Settings
  String? _googleClientId;
  String? _googleClientSecret;
  int _syncIntervalMinutes = 30;

  // Project Settings
  String? _masterDirectoryPath;
  String? _currentProjectName;
  List<ProjectInfo> _availableProjects = [];

  SettingsProvider({SettingsDatabase? settingsDatabase, StorageService? storageService}) 
      : _db = settingsDatabase ?? SettingsDatabase.instance,
        _storageService = storageService ?? (kIsWeb ? StorageService(fileSystem: MemoryFileSystem()) : StorageService()) {
    _startSessionTracker();
    _startAlarmChecker();
  }

  Future<void> loadSettings() async {
    _mirroredProjects = await _db.getMirroredProjects();
    final settings = await _db.getSettings();
    _clockEnabled = settings['clock_enabled'] == 1;
    _currentSessionEnabled = settings['current_session_enabled'] == 1;
    _targetSessionEnabled = settings['target_session_enabled'] == 1;
    _focusTimerEnabled = settings['focus_timer_enabled'] == 1;
    _batteryGuardEnabled = (settings['battery_guard_enabled'] ?? 1) == 1;
    _batteryAlertThreshold = settings['battery_alert_threshold'] ?? 20;
    _showBatteryPercentage = (settings['show_battery_percentage'] ?? 1) == 1;
    _lastNotesFullscreenState = (settings['last_notes_fullscreen_state'] ?? 0) == 1;
    _typewriterEnabled = (settings['typewriter_enabled'] ?? 0) == 1;
    _paragraphFocusEnabled = (settings['paragraph_focus_enabled'] ?? 0) == 1;
    _codexLinkingEnabled = (settings['codex_linking_enabled'] ?? 0) == 1;
    _tocWordCountsEnabled = (settings['toc_word_counts_enabled'] ?? 1) == 1;
    _dailyWordGoal = settings['daily_word_goal'] ?? 0;
    _spellCheckEnabled = (settings['spell_check_enabled'] ?? 1) == 1;
    _googleClientId = settings['google_client_id'];
    _googleClientSecret = settings['google_client_secret'];
    _syncIntervalMinutes = settings['sync_interval_minutes'] ?? 30;
    _masterDirectoryPath = settings['master_directory_path'];
    _currentProjectName = settings['current_project_name'];

    // On macOS (App Sandbox) a raw path grants no access after relaunch. Resolve
    // the security-scoped bookmark saved when the folder was picked, begin
    // accessing it, and hold that access for the app's lifetime (never stop).
    if (!kIsWeb && Platform.isMacOS) {
      final String? bookmark = settings['master_directory_bookmark'] as String?;
      if (bookmark != null && bookmark.isNotEmpty) {
        try {
          final resolved =
              await _bookmarks.resolveBookmark(bookmark, isDirectory: true);
          await _bookmarks.startAccessingSecurityScopedResource(resolved);
          _masterDirectoryPath = resolved.path;
        } catch (e) {
          // Stale/invalid bookmark: treat as no folder so the UI prompts
          // re-selection rather than failing to read an inaccessible path.
          _masterDirectoryPath = null;
        }
      } else if (_masterDirectoryPath != null) {
        // A path persisted by a pre-sandbox build but no bookmark exists. Under
        // the sandbox that path is unusable, so force re-selection.
        _masterDirectoryPath = null;
      }
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && _masterDirectoryPath == null) {
      final docDir = await getApplicationDocumentsDirectory();
      _masterDirectoryPath = docDir.path;
      await _db.updateSetting('master_directory_path', _masterDirectoryPath);
    }
    
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
  bool get typewriterEnabled => _typewriterEnabled;
  bool get paragraphFocusEnabled => _paragraphFocusEnabled;
  bool get codexLinkingEnabled => _codexLinkingEnabled;
  bool get tocWordCountsEnabled => _tocWordCountsEnabled;
  int get dailyWordGoal => _dailyWordGoal;
  bool get hasDailyWordGoal => _dailyWordGoal > 0;
  String? get googleClientId => _googleClientId;
  String? get googleClientSecret => _googleClientSecret;
  int get syncIntervalMinutes => _syncIntervalMinutes;
  bool get spellCheckEnabled => _spellCheckEnabled;

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

  void toggleTypewriter(bool enabled) {
    _typewriterEnabled = enabled;
    _db.updateSetting('typewriter_enabled', enabled);
    notifyListeners();
  }

  void toggleParagraphFocus(bool enabled) {
    _paragraphFocusEnabled = enabled;
    _db.updateSetting('paragraph_focus_enabled', enabled);
    notifyListeners();
  }

  void toggleSpellCheck(bool enabled) {
    _spellCheckEnabled = enabled;
    _db.updateSetting('spell_check_enabled', enabled);
    notifyListeners();
  }

  void toggleCodexLinking(bool enabled) {
    _codexLinkingEnabled = enabled;
    _db.updateSetting('codex_linking_enabled', enabled);
    notifyListeners();
  }

  void toggleTocWordCounts(bool enabled) {
    _tocWordCountsEnabled = enabled;
    _db.updateSetting('toc_word_counts_enabled', enabled);
    notifyListeners();
  }

  void setDailyWordGoal(int goal) {
    _dailyWordGoal = goal < 0 ? 0 : goal;
    _db.updateSetting('daily_word_goal', _dailyWordGoal);
    notifyListeners();
  }

  void setLastNotesFullscreenState(bool isFullscreen) {
    _lastNotesFullscreenState = isFullscreen;
    _db.updateSetting('last_notes_fullscreen_state', isFullscreen);
    notifyListeners();
  }

  Future<void> setGoogleCredentials(String? clientId, String? clientSecret) async {
    _googleClientId = clientId;
    _googleClientSecret = clientSecret;
    await _db.updateSetting('google_client_id', clientId);
    await _db.updateSetting('google_client_secret', clientSecret);
    notifyListeners();
  }

  Future<void> setMasterDirectory(String? path) async {
    _masterDirectoryPath = path;
    _db.updateSetting('master_directory_path', path);

    // On macOS (App Sandbox) persist a security-scoped bookmark so we can regain
    // access to this folder after relaunch. The just-picked folder is already
    // accessible this session, so no startAccessing call is needed here. Other
    // platforms keep the raw-path behavior unchanged.
    if (!kIsWeb && Platform.isMacOS) {
      if (path != null) {
        try {
          final bookmark = await _bookmarks.bookmark(Directory(path));
          await _db.updateSetting('master_directory_bookmark', bookmark);
        } catch (e) {
          // If bookmark creation fails, clear any stale value.
          await _db.updateSetting('master_directory_bookmark', null);
        }
      } else {
        await _db.updateSetting('master_directory_bookmark', null);
      }
    }

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

  /// True when [projectName] is a mirror of a Drive project owned by another
  /// device. Null and unknown names are not mirrors: absence means ours.
  bool isMirroredProject(String? projectName) =>
      projectName != null && _mirroredProjects.contains(projectName);

  Set<String> get mirroredProjects => Set.unmodifiable(_mirroredProjects);

  /// Records that [projectName] was pulled from Drive rather than written here.
  Future<void> markProjectMirrored(String projectName) async {
    await _db.markProjectMirrored(projectName);
    _mirroredProjects = await _db.getMirroredProjects();
    notifyListeners();
  }

  /// Forks a mirrored project into one this device owns, and makes it current.
  ///
  /// A NEW fork is seeded with [seedContent] when given — the editor's live
  /// text, so the keystroke that triggered the fork is carried across rather
  /// than swallowed — and otherwise with the mirror's content on disk.
  ///
  /// An EXISTING fork is reused and never refreshed: it holds edits from an
  /// earlier session on this device, and overwriting them with the mirror's
  /// copy would destroy the work this mechanism exists to protect. The rule
  /// is one line: a new fork takes what is on screen, an existing fork is
  /// opened untouched.
  Future<ForkResult> forkMirroredProject({
    required String sourceName,
    required ForkDevice device,
    String? seedContent,
  }) async {
    final master = _masterDirectoryPath;
    if (master == null) {
      return ForkResult(
        sourceName: sourceName,
        forkName: sourceName,
        outcome: ForkOutcome.failed,
        error: StateError('No master directory is set.'),
      );
    }

    final forkName = forkNameFor(sourceName, forkSuffixFor(device));

    try {
      final existing = await _storageService.listProjects(master);
      final alreadyForked =
          existing.any((n) => n.toLowerCase() == forkName.toLowerCase());

      if (!alreadyForked) {
        final sourcePath = '$master/$sourceName';
        final read = await _storageService.readDocument(sourcePath);
        if (seedContent == null && read.failed) {
          // Refuse rather than seed a fork with a blank: the mirror's real
          // content is unknown, and a blank fork would look like a project
          // whose words were deleted.
          return ForkResult(
            sourceName: sourceName,
            forkName: forkName,
            outcome: ForkOutcome.failed,
            error: read.error,
          );
        }

        await _storageService.initProject(master, forkName,
            initialContent: seedContent ?? read.value);

        final forkPath = '$master/$forkName';
        final notes = await _storageService.readNotes(sourcePath);
        if (!notes.failed && notes.value.isNotEmpty) {
          await _storageService.saveNotes(
              forkPath, List<NoteCard>.from(notes.value));
        }
        final stats = await _storageService.readProjectStats(sourcePath);
        await _storageService.saveProjectStats(forkPath, stats);
      }

      await refreshProjects();
      await setCurrentProject(forkName);

      return ForkResult(
        sourceName: sourceName,
        forkName: forkName,
        outcome: alreadyForked ? ForkOutcome.reused : ForkOutcome.created,
      );
    } catch (e) {
      return ForkResult(
        sourceName: sourceName,
        forkName: forkName,
        outcome: ForkOutcome.failed,
        error: e,
      );
    }
  }

  Future<bool> createProject(String name) async {
    if (_masterDirectoryPath == null) return false;
    if (!StorageService.isValidProjectName(name)) return false;
    final cleanName = name.trim();
    await _storageService.initProject(_masterDirectoryPath!, cleanName);
    await refreshProjects();
    await setCurrentProject(cleanName);
    return true;
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

  Future<bool> renameProject(String oldName, String newName) async {
    if (_masterDirectoryPath == null) return false;
    if (oldName == 'User Manual') return false; // Protect User Manual
    final cleanName = newName.trim();
    if (cleanName.isEmpty || cleanName == oldName) return false;
    if (!StorageService.isValidProjectName(cleanName)) return false;

    try {
      final success = await _storageService.renameProject(_masterDirectoryPath!, oldName, cleanName);
      if (!success) return false;

      if (_currentProjectName == oldName) {
        _currentProjectName = cleanName;
        await _db.updateSetting('current_project_name', cleanName);
      }

      // A renamed mirror keeps being a mirror, but under its new name — the
      // old name left behind would shadow any unrelated project later given
      // it, silently making that one unwritable.
      if (_mirroredProjects.contains(oldName)) {
        await _db.unmarkProjectMirrored(oldName);
        await _db.markProjectMirrored(cleanName);
        _mirroredProjects = await _db.getMirroredProjects();
      }

      await refreshProjects();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> updateSyncInterval(int minutes) async {
    _syncIntervalMinutes = minutes;
    await _db.updateSetting('sync_interval_minutes', minutes);
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _pomodoroTimer?.cancel();
    super.dispose();
  }
}
