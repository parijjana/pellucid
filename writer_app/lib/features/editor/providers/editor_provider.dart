// @trace FEAT-20260516-120000-0001
// Description: Provider for managing editor state and auto-saving (Updated for Multi-Project).

import 'dart:async';
import 'package:flutter/material.dart';
import 'storage_service.dart';
import '../../settings/providers/settings_database.dart';

import '../../sync/providers/sync_provider.dart';

class EditorProvider extends ChangeNotifier {
  final StorageService _storageService;
  final SettingsDatabase _db;
  
  String _content = StorageService.userManualContent;
  String? _currentProjectPath;
  double _zoomLevel = 1.0;
  double _pageWidth = 800.0;
  double _horizontalPosition = 0.5;
  Timer? _debounceTimer;

  EditorProvider({StorageService? storageService, SettingsDatabase? settingsDatabase}) 
      : _storageService = storageService ?? StorageService(),
        _db = settingsDatabase ?? SettingsDatabase.instance;

  String get content => _content;
  double get zoomLevel => _zoomLevel;
  double get pageWidth => _pageWidth;
  double get horizontalPosition => _horizontalPosition;

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
    _currentProjectPath = projectPath;
    if (projectPath == null) {
      _content = StorageService.userManualContent;
    } else {
      _content = await _storageService.readDocument(projectPath);
    }
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
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      await _storageService.saveDocument(_currentProjectPath!, _content);
      if (syncProvider != null && projectName != null) {
        await syncProvider.syncCurrentFile(
          projectName: projectName,
          fileName: 'manuscript.md',
          content: _content,
        );
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
