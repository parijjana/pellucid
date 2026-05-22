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
  List<String> _categories = ['general', 'people', 'places', 'events'];
  String? _currentProjectPath;
  String? _currentProjectName;

  NotesProvider({StorageService? storageService}) 
      : _storageService = storageService ?? StorageService();

  List<NoteCard> get cards => List.unmodifiable(_cards);
  List<String> get categories => List.unmodifiable(_categories);

  Future<void> loadProject(String? projectPath, {String? projectName}) async {
    _currentProjectPath = projectPath;
    _currentProjectName = projectName;
    if (projectPath == null) {
      _cards = [];
      _categories = ['general', 'people', 'places', 'events'];
    } else {
      _cards = await _storageService.readNotes(projectPath);
      _categories = await _storageService.readCategories(projectPath);
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

  Future<void> addCategory(String category) async {
    final normalized = category.trim().toLowerCase();
    if (normalized.isNotEmpty && !_categories.contains(normalized)) {
      _categories.add(normalized);
      if (_currentProjectPath != null) {
        await _storageService.saveCategories(_currentProjectPath!, _categories);
      }
      notifyListeners();
    }
  }

  void addCard({String category = 'general', SyncProvider? syncProvider}) {
    _cards.add(NoteCard(title: 'New Note', content: '', category: category));
    _save(syncProvider: syncProvider);
    notifyListeners();
  }

  void addAttributionCard({SyncProvider? syncProvider}) {
    if (_cards.any((card) => card.isAttribution)) return;
    _cards.add(NoteCard(
      title: 'Attributions',
      content: '',
      category: 'general',
      isAttribution: true,
      attributionItems: const [],
      attributionType: 'bullet',
    ));
    _save(syncProvider: syncProvider);
    notifyListeners();
  }

  void updateCard(
    String id, {
    String? title,
    String? content,
    String? category,
    bool? isAttribution,
    String? sourceUrl,
    List<AttributionItem>? attributionItems,
    String? attributionType,
    SyncProvider? syncProvider,
  }) {
    final index = _cards.indexWhere((card) => card.id == id);
    if (index != -1) {
      _cards[index] = _cards[index].copyWith(
        title: title,
        content: content,
        category: category,
        isAttribution: isAttribution,
        sourceUrl: sourceUrl,
        attributionItems: attributionItems,
        attributionType: attributionType,
      );
      _save(syncProvider: syncProvider);
      notifyListeners();
    }
  }

  void connectCards(String id1, String id2, {SyncProvider? syncProvider}) {
    final index1 = _cards.indexWhere((card) => card.id == id1);
    final index2 = _cards.indexWhere((card) => card.id == id2);
    if (index1 != -1 && index2 != -1) {
      bool changed = false;
      if (!_cards[index1].connections.contains(id2)) {
        final updatedConnections = List<String>.from(_cards[index1].connections)..add(id2);
        _cards[index1] = _cards[index1].copyWith(connections: updatedConnections);
        changed = true;
      }
      if (!_cards[index2].connections.contains(id1)) {
        final updatedConnections = List<String>.from(_cards[index2].connections)..add(id1);
        _cards[index2] = _cards[index2].copyWith(connections: updatedConnections);
        changed = true;
      }
      if (changed) {
        _save(syncProvider: syncProvider);
        notifyListeners();
      }
    }
  }

  void disconnectCards(String id1, String id2, {SyncProvider? syncProvider}) {
    final index1 = _cards.indexWhere((card) => card.id == id1);
    final index2 = _cards.indexWhere((card) => card.id == id2);
    if (index1 != -1 && index2 != -1) {
      bool changed = false;
      if (_cards[index1].connections.contains(id2)) {
        final updatedConnections = List<String>.from(_cards[index1].connections)..remove(id2);
        _cards[index1] = _cards[index1].copyWith(connections: updatedConnections);
        changed = true;
      }
      if (_cards[index2].connections.contains(id1)) {
        final updatedConnections = List<String>.from(_cards[index2].connections)..remove(id1);
        _cards[index2] = _cards[index2].copyWith(connections: updatedConnections);
        changed = true;
      }
      if (changed) {
        _save(syncProvider: syncProvider);
        notifyListeners();
      }
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
