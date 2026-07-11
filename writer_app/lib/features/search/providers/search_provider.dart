import 'package:flutter/material.dart';

class SearchProvider extends ChangeNotifier {
  String _query = '';
  bool _isSearchOpen = false;
  int _currentMatchIndex = -1;
  final List<int> _matchOffsets = [];

  // Replace (Phase 1): a second, independent text field revealed by a ghost
  // chevron toggle. Matching always mirrors search (case-insensitive
  // substring) — there is no match-case/whole-word toggle in v1.
  String _replaceQuery = '';
  bool _replaceMode = false;

  String get query => _query;
  bool get isSearchOpen => _isSearchOpen;
  int get currentMatchIndex => _currentMatchIndex;
  List<int> get matchOffsets => _matchOffsets;
  String get replaceQuery => _replaceQuery;
  bool get replaceMode => _replaceMode;

  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    notifyListeners();
  }

  void setReplaceQuery(String q) {
    if (_replaceQuery == q) return;
    _replaceQuery = q;
    notifyListeners();
  }

  void toggleReplaceMode({bool? isOpen}) {
    final nextState = isOpen ?? !_replaceMode;
    if (_replaceMode == nextState) return;
    _replaceMode = nextState;
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
      _replaceQuery = '';
      _replaceMode = false;
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
