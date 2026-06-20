import 'package:flutter/material.dart';

class SearchProvider extends ChangeNotifier {
  String _query = '';
  bool _isSearchOpen = false;
  int _currentMatchIndex = -1;
  final List<int> _matchOffsets = [];

  String get query => _query;
  bool get isSearchOpen => _isSearchOpen;
  int get currentMatchIndex => _currentMatchIndex;
  List<int> get matchOffsets => _matchOffsets;

  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    notifyListeners();
  }

  void updateMatchOffsets(String text) {
    _matchOffsets.clear();
    if (_query.isEmpty) {
      _currentMatchIndex = -1;
      notifyListeners();
      return;
    }
    
    final escaped = RegExp.escape(_query);
    final regex = RegExp(escaped, caseSensitive: false);
    final matches = regex.allMatches(text);
    for (final match in matches) {
      _matchOffsets.add(match.start);
    }
    
    if (_matchOffsets.isNotEmpty) {
      if (_currentMatchIndex < 0 || _currentMatchIndex >= _matchOffsets.length) {
        _currentMatchIndex = 0;
      }
    } else {
      _currentMatchIndex = -1;
    }
    notifyListeners();
  }

  void nextMatch() {
    if (_matchOffsets.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _matchOffsets.length;
    notifyListeners();
  }

  void previousMatch() {
    if (_matchOffsets.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex - 1 + _matchOffsets.length) % _matchOffsets.length;
    notifyListeners();
  }

  void toggleSearch({bool? isOpen}) {
    final nextState = isOpen ?? !_isSearchOpen;
    if (_isSearchOpen == nextState) return;
    _isSearchOpen = nextState;
    if (!_isSearchOpen) {
      _query = ''; // Clear search query when closing search
      _matchOffsets.clear();
      _currentMatchIndex = -1;
    }
    notifyListeners();
  }

  void clear() {
    if (_query.isEmpty) return;
    _query = '';
    _matchOffsets.clear();
    _currentMatchIndex = -1;
    notifyListeners();
  }
}
