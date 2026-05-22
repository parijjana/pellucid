import 'package:flutter/material.dart';

class ShortcutsProvider extends ChangeNotifier {
  bool _isClockPeeked = false;
  bool _isSessionPeeked = false;
  
  // UI Panel States
  bool _isLeftSidebarOpen = false;
  bool _isRightSidebarOpen = false;
  bool _isToolbarOpen = false;
  bool _isFullscreen = false;

  bool get isClockPeeked => _isClockPeeked;
  bool get isSessionPeeked => _isSessionPeeked;
  
  bool get isLeftSidebarOpen => _isLeftSidebarOpen;
  bool get isRightSidebarOpen => _isRightSidebarOpen;
  bool get isToolbarOpen => _isToolbarOpen;
  bool get isFullscreen => _isFullscreen;

  void peekClock() {
    _isClockPeeked = true;
    notifyListeners();
    Future.delayed(const Duration(seconds: 2), () {
      _isClockPeeked = false;
      notifyListeners();
    });
  }

  void peekSession() {
    _isSessionPeeked = true;
    notifyListeners();
    Future.delayed(const Duration(seconds: 2), () {
      _isSessionPeeked = false;
      notifyListeners();
    });
  }

  void toggleLeftSidebar() {
    _isLeftSidebarOpen = !_isLeftSidebarOpen;
    notifyListeners();
  }

  void toggleRightSidebar() {
    _isRightSidebarOpen = !_isRightSidebarOpen;
    notifyListeners();
  }

  void toggleToolbar() {
    _isToolbarOpen = !_isToolbarOpen;
    notifyListeners();
  }

  void setFullscreen(bool value) {
    _isFullscreen = value;
    notifyListeners();
  }
}
