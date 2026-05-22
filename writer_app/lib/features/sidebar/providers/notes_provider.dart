// @trace FEAT-20260516-114400-0002
// Description: Provider for managing sidebar notes (Persistent & Multi-Project).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'note_card.dart';
import '../../editor/providers/storage_service.dart';
import '../../sync/providers/sync_provider.dart';

class NotesProvider extends ChangeNotifier {
  final StorageService _storageService;
  List<NoteCard> _cards = [];
  String? _currentProjectPath;
  String? _currentProjectName;

  NotesProvider({StorageService? storageService}) 
      : _storageService = storageService ?? StorageService();

  List<NoteCard> get cards => List.unmodifiable(_cards);

  Future<void> loadProject(String? projectPath, {String? projectName}) async {
    _currentProjectPath = projectPath;
    _currentProjectName = projectName;
    if (projectPath == null) {
      _cards = [];
    } else {
      _cards = await _storageService.readNotes(projectPath);
    }
    notifyListeners();
  }

  void _save({SyncProvider? syncProvider}) {
    if (_currentProjectPath != null) {
      _storageService.saveNotes(_currentProjectPath!, _cards);
      
      if (syncProvider != null && syncProvider.isLoggedIn && _currentProjectName != null) {
        final notesJson = jsonEncode(_cards.map((c) => c.toJson()).toList());
        syncProvider.syncNotes(
          projectName: _currentProjectName!,
          notesJson: notesJson,
        );
      }
    }
  }

  void addCard({NoteCategory category = NoteCategory.general, SyncProvider? syncProvider}) {
    _cards.add(NoteCard(title: 'New Note', content: '', category: category));
    _save(syncProvider: syncProvider);
    notifyListeners();
  }

  void updateCard(String id, {String? title, String? content, NoteCategory? category, SyncProvider? syncProvider}) {
    final index = _cards.indexWhere((card) => card.id == id);
    if (index != -1) {
      _cards[index] = _cards[index].copyWith(
        title: title,
        content: content,
        category: category,
      );
      _save(syncProvider: syncProvider);
      notifyListeners();
    }
  }

  void connectCards(String id1, String id2, {SyncProvider? syncProvider}) {
    final index1 = _cards.indexWhere((card) => card.id == id1);
    if (index1 != -1 && !_cards[index1].connections.contains(id2)) {
      final updatedConnections = List<String>.from(_cards[index1].connections)..add(id2);
      _cards[index1] = _cards[index1].copyWith(connections: updatedConnections);
      _save(syncProvider: syncProvider);
      notifyListeners();
    }
  }

  void deleteCard(String id, {SyncProvider? syncProvider}) {
    _cards.removeWhere((card) => card.id == id);
    for (int i = 0; i < _cards.length; i++) {
      if (_cards[i].connections.contains(id)) {
        _cards[i] = _cards[i].copyWith(
          connections: List<String>.from(_cards[i].connections)..remove(id),
        );
      }
    }
    _save(syncProvider: syncProvider);
    notifyListeners();
  }
}
