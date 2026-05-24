import 'package:flutter/material.dart';
import 'note_card.dart';
import 'notes_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';

class NoteEditorController extends ChangeNotifier {
  String currentNoteId;
  final List<String> navigationHistory = [];

  final TextEditingController titleController = TextEditingController();
  final TextEditingController contentController = TextEditingController();
  final TextEditingController sourceUrlController = TextEditingController();
  final TextEditingController newCategoryController = TextEditingController();

  String selectedCategory = 'general';
  bool isAttribution = false;
  bool isFullScreen = false;

  List<AttributionItem> attributionItems = [];
  String attributionType = 'bullet';

  NoteEditorController({
    required this.currentNoteId,
    required bool initialFullScreen,
  }) : isFullScreen = initialFullScreen;

  void init(NotesProvider provider) {
    _loadNote(currentNoteId, provider);
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    sourceUrlController.dispose();
    newCategoryController.dispose();
    super.dispose();
  }

  void _loadNote(String noteId, NotesProvider provider) {
    final cardIndex = provider.cards.indexWhere((c) => c.id == noteId);
    if (cardIndex != -1) {
      final card = provider.cards[cardIndex];
      currentNoteId = noteId;
      titleController.text = card.title;
      contentController.text = card.content;
      sourceUrlController.text = card.sourceUrl ?? '';
      selectedCategory = card.category;
      isAttribution = card.isAttribution;
      attributionItems = card.attributionItems != null ? List<AttributionItem>.from(card.attributionItems!) : [];
      if (isAttribution && attributionItems.isEmpty) {
        attributionItems = [AttributionItem(text: '')];
      }
      attributionType = card.attributionType;
      notifyListeners();
    }
  }

  void saveCurrentNoteState({
    required NotesProvider provider,
    required SyncProvider sync,
    required EditorProvider editor,
    required SettingsProvider settings,
  }) {
    provider.updateCard(
      currentNoteId,
      title: titleController.text,
      content: contentController.text,
      category: selectedCategory,
      isAttribution: isAttribution,
      sourceUrl: sourceUrlController.text.trim().isEmpty ? null : sourceUrlController.text.trim(),
      attributionItems: isAttribution ? attributionItems : null,
      attributionType: attributionType,
      syncProvider: sync,
    );

    // Sync to manuscript if this is an attribution note
    final updatedCardIndex = provider.cards.indexWhere((c) => c.id == currentNoteId);
    if (updatedCardIndex != -1) {
      final updatedCard = provider.cards[updatedCardIndex];
      if (updatedCard.isAttribution) {
        editor.syncAttributions(
          updatedCard,
          syncProvider: sync,
          projectName: settings.currentProjectName,
        );
      }
    }
  }

  void navigateToNote(String nextNoteId, NotesProvider provider, SyncProvider sync, EditorProvider editor, SettingsProvider settings) {
    saveCurrentNoteState(provider: provider, sync: sync, editor: editor, settings: settings);
    navigationHistory.add(currentNoteId);
    _loadNote(nextNoteId, provider);
  }

  void goBack(NotesProvider provider, SyncProvider sync, EditorProvider editor, SettingsProvider settings) {
    if (navigationHistory.isNotEmpty) {
      saveCurrentNoteState(provider: provider, sync: sync, editor: editor, settings: settings);
      final prevNoteId = navigationHistory.removeLast();
      _loadNote(prevNoteId, provider);
    }
  }

  void cycleCategory(NotesProvider provider) {
    final cats = provider.categories;
    final idx = cats.indexOf(selectedCategory);
    selectedCategory = cats[idx == -1 ? 0 : (idx + 1) % cats.length];
    notifyListeners();
  }

  void updateAttributionType(String type, NotesProvider provider, SyncProvider sync, EditorProvider editor, SettingsProvider settings) {
    attributionType = type;
    notifyListeners();
    saveCurrentNoteState(provider: provider, sync: sync, editor: editor, settings: settings);
  }

  void updateAttributionItemText(int index, String text, NotesProvider provider, SyncProvider sync, EditorProvider editor, SettingsProvider settings) {
    attributionItems[index] = attributionItems[index].copyWith(text: text);
    notifyListeners();
    saveCurrentNoteState(provider: provider, sync: sync, editor: editor, settings: settings);
  }

  void addAttributionItem(int index, String text, NotesProvider provider, SyncProvider sync, EditorProvider editor, SettingsProvider settings) {
    if (index == -1) {
      attributionItems.add(AttributionItem(text: text));
    } else {
      attributionItems.insert(index + 1, AttributionItem(text: text));
    }
    notifyListeners();
    saveCurrentNoteState(provider: provider, sync: sync, editor: editor, settings: settings);
  }

  void linkNoteToItem(int index, String targetNoteId, NotesProvider provider, SyncProvider sync, EditorProvider editor, SettingsProvider settings) {
    final item = attributionItems[index];
    if (!item.connections.contains(targetNoteId)) {
      final updatedConnections = List<String>.from(item.connections)..add(targetNoteId);
      attributionItems[index] = item.copyWith(connections: updatedConnections);
    }
    provider.connectCards(currentNoteId, targetNoteId, syncProvider: sync);
    notifyListeners();
    saveCurrentNoteState(provider: provider, sync: sync, editor: editor, settings: settings);
  }

  void unlinkNoteFromItem(int index, String targetNoteId, NotesProvider provider, SyncProvider sync, EditorProvider editor, SettingsProvider settings) {
    final item = attributionItems[index];
    final updatedConnections = List<String>.from(item.connections)..remove(targetNoteId);
    attributionItems[index] = item.copyWith(connections: updatedConnections);

    bool stillLinked = false;
    for (var item in attributionItems) {
      if (item.connections.contains(targetNoteId)) {
        stillLinked = true;
        break;
      }
    }
    if (!stillLinked) {
      provider.disconnectCards(currentNoteId, targetNoteId, syncProvider: sync);
    }
    notifyListeners();
    saveCurrentNoteState(provider: provider, sync: sync, editor: editor, settings: settings);
  }

  void deleteAttributionItem(int index, NotesProvider provider, SyncProvider sync, EditorProvider editor, SettingsProvider settings) {
    final item = attributionItems[index];

    for (var targetNoteId in item.connections) {
      bool stillLinked = false;
      for (int i = 0; i < attributionItems.length; i++) {
        if (i == index) continue;
        if (attributionItems[i].connections.contains(targetNoteId)) {
          stillLinked = true;
          break;
        }
      }
      if (!stillLinked) {
        provider.disconnectCards(currentNoteId, targetNoteId, syncProvider: sync);
      }
    }

    attributionItems.removeAt(index);
    notifyListeners();
    saveCurrentNoteState(provider: provider, sync: sync, editor: editor, settings: settings);
  }

  void setFullScreen(bool value) {
    isFullScreen = value;
    notifyListeners();
  }

  void setIsAttribution(bool value) {
    isAttribution = value;
    notifyListeners();
  }

  void setSelectedCategory(String value) {
    selectedCategory = value;
    notifyListeners();
  }
}
