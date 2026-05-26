import 'package:flutter/material.dart';

class SearchProvider extends ChangeNotifier {
  String _query = '';
  bool _isSearchOpen = false;

  String get query => _query;
  bool get isSearchOpen => _isSearchOpen;

  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    notifyListeners();
  }

  void toggleSearch({bool? isOpen}) {
    final nextState = isOpen ?? !_isSearchOpen;
    if (_isSearchOpen == nextState) return;
    _isSearchOpen = nextState;
    if (!_isSearchOpen) {
      _query = ''; // Clear search query when closing search
    }
    notifyListeners();
  }

  void clear() {
    if (_query.isEmpty) return;
    _query = '';
    notifyListeners();
  }
}
