// @trace FEAT-20260522-0001
// Description: Dual-mode note editor dialog (Popup and Fullscreen overlay).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/note_card.dart';
import '../providers/notes_provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';
import 'note_editor_power_panel.dart';
import 'note_editor_standard_field.dart';
import 'note_editor_attribution_list.dart';
import 'note_editor_top_bar.dart';

class NoteEditorDialog extends StatefulWidget {
  final String noteId;

  const NoteEditorDialog({super.key, required this.noteId});

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  String _currentNoteId = '';
  final List<String> _navigationHistory = [];

  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _sourceUrlController;
  late TextEditingController _newCategoryController;
  String _selectedCategory = 'general';
  bool _isAttribution = false;
  bool _isFullScreen = false;

  List<AttributionItem> _attributionItems = [];
  String _attributionType = 'bullet';

  @override
  void initState() {
    super.initState();
    _currentNoteId = widget.noteId;
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _sourceUrlController = TextEditingController();
    _newCategoryController = TextEditingController();

    final settings = context.read<SettingsProvider>();
    _isFullScreen = settings.lastNotesFullscreenState;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNote(_currentNoteId);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _sourceUrlController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }

  void _loadNote(String noteId) {
    final provider = context.read<NotesProvider>();
    final cardIndex = provider.cards.indexWhere((c) => c.id == noteId);
    if (cardIndex != -1) {
      final card = provider.cards[cardIndex];
      setState(() {
        _currentNoteId = noteId;
        _titleController.text = card.title;
        _contentController.text = card.content;
        _sourceUrlController.text = card.sourceUrl ?? '';
        _selectedCategory = card.category;
        _isAttribution = card.isAttribution;
        _attributionItems = card.attributionItems != null ? List<AttributionItem>.from(card.attributionItems!) : [];
        if (_isAttribution && _attributionItems.isEmpty) {
          _attributionItems = [AttributionItem(text: '')];
        }
        _attributionType = card.attributionType;
      });
      // Save state if we auto-created the first item
      if (card.isAttribution && (card.attributionItems == null || card.attributionItems!.isEmpty)) {
        _saveCurrentNoteState();
      }
    }
  }

  void _saveCurrentNoteState() {
    final provider = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final settings = context.read<SettingsProvider>();
    final editor = context.read<EditorProvider>();

    provider.updateCard(
      _currentNoteId,
      title: _titleController.text,
      content: _contentController.text,
      category: _selectedCategory,
      isAttribution: _isAttribution,
      sourceUrl: _sourceUrlController.text.trim().isEmpty ? null : _sourceUrlController.text.trim(),
      attributionItems: _isAttribution ? _attributionItems : null,
      attributionType: _attributionType,
      syncProvider: sync,
    );

    // Sync to manuscript if this is an attribution note
    final updatedCard = provider.cards.firstWhere((c) => c.id == _currentNoteId);
    if (updatedCard.isAttribution) {
      editor.syncAttributions(
        updatedCard,
        syncProvider: sync,
        projectName: settings.currentProjectName,
      );
    }
  }

  void _navigateToNote(String nextNoteId) {
    _saveCurrentNoteState();
    setState(() {
      _navigationHistory.add(_currentNoteId);
      _loadNote(nextNoteId);
    });
  }

  void _goBack() {
    if (_navigationHistory.isNotEmpty) {
      _saveCurrentNoteState();
      setState(() {
        final prevNoteId = _navigationHistory.removeLast();
        _loadNote(prevNoteId);
      });
    }
  }

  void _cycleCategory() {
    final provider = context.read<NotesProvider>();
    final cats = provider.categories;
    final idx = cats.indexOf(_selectedCategory);
    setState(() {
      _selectedCategory = cats[idx == -1 ? 0 : (idx + 1) % cats.length];
    });
  }

  void _linkNoteToItem(int index, String targetNoteId) {
    final sync = context.read<SyncProvider>();
    final provider = context.read<NotesProvider>();
    setState(() {
      final item = _attributionItems[index];
      if (!item.connections.contains(targetNoteId)) {
        final updatedConnections = List<String>.from(item.connections)..add(targetNoteId);
        _attributionItems[index] = item.copyWith(connections: updatedConnections);
      }
    });
    provider.connectCards(_currentNoteId, targetNoteId, syncProvider: sync);
    _saveCurrentNoteState();
  }

  void _unlinkNoteFromItem(int index, String targetNoteId) {
    final sync = context.read<SyncProvider>();
    final provider = context.read<NotesProvider>();
    setState(() {
      final item = _attributionItems[index];
      final updatedConnections = List<String>.from(item.connections)..remove(targetNoteId);
      _attributionItems[index] = item.copyWith(connections: updatedConnections);
    });

    bool stillLinked = false;
    for (var item in _attributionItems) {
      if (item.connections.contains(targetNoteId)) {
        stillLinked = true;
        break;
      }
    }
    if (!stillLinked) {
      provider.disconnectCards(_currentNoteId, targetNoteId, syncProvider: sync);
    }
    _saveCurrentNoteState();
  }

  void _deleteAttributionItem(int index) {
    final sync = context.read<SyncProvider>();
    final provider = context.read<NotesProvider>();
    final item = _attributionItems[index];

    for (var targetNoteId in item.connections) {
      bool stillLinked = false;
      for (int i = 0; i < _attributionItems.length; i++) {
        if (i == index) continue;
        if (_attributionItems[i].connections.contains(targetNoteId)) {
          stillLinked = true;
          break;
        }
      }
      if (!stillLinked) {
        provider.disconnectCards(_currentNoteId, targetNoteId, syncProvider: sync);
      }
    }

    setState(() {
      _attributionItems.removeAt(index);
    });
    _saveCurrentNoteState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final provider = context.watch<NotesProvider>();
    final settings = context.watch<SettingsProvider>();

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    // Viewport Sizing Mandate: 70% width and 50% height for popup mode.
    final double width = _isFullScreen ? screenWidth : screenWidth * 0.7;
    final double height = _isFullScreen ? screenHeight : screenHeight * 0.5;

    final currentCardIndex = provider.cards.indexWhere((c) => c.id == _currentNoteId);
    final currentCard = currentCardIndex != -1 ? provider.cards[currentCardIndex] : null;

    if (currentCard == null) {
      return const SizedBox.shrink();
    }

    return Dialog(
      constraints: BoxConstraints.tightFor(width: width, height: height),
      insetPadding: _isFullScreen ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      backgroundColor: Colors.transparent,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final isAlt = HardwareKeyboard.instance.isAltPressed;
            if (isAlt && event.logicalKey == LogicalKeyboardKey.keyB) {
              _saveCurrentNoteState();
              Navigator.pop(context);
              return KeyEventResult.handled;
            }
            if (isAlt && event.logicalKey == LogicalKeyboardKey.keyM) {
              _cycleCategory();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: theme.sidebarColor,
            borderRadius: _isFullScreen ? BorderRadius.zero : BorderRadius.circular(16),
            boxShadow: theme.sidebarShadows,
          ),
          child: Column(
            children: [
              NoteEditorTopBar(
                theme: theme,
                isAttribution: _isAttribution,
                isFullScreen: _isFullScreen,
                showBackButton: _navigationHistory.isNotEmpty,
                onBackPressed: _goBack,
                onToggleFullScreen: () {
                  setState(() {
                    _isFullScreen = !_isFullScreen;
                    settings.setLastNotesFullscreenState(_isFullScreen);
                  });
                },
                onClosePressed: () {
                  _saveCurrentNoteState();
                  Navigator.pop(context);
                },
              ),
              Expanded(
                child: _isFullScreen
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _buildEditor(theme),
                          ),
                          VerticalDivider(width: 1, color: theme.foregroundColor.withValues(alpha: 0.1)),
                          Expanded(
                            flex: 3,
                            child: NoteEditorPowerPanel(
                              theme: theme,
                              provider: provider,
                              currentCard: currentCard,
                              isAttribution: _isAttribution,
                              sourceUrlController: _sourceUrlController,
                              newCategoryController: _newCategoryController,
                              selectedCategory: _selectedCategory,
                              onIsAttributionChanged: (val) => setState(() => _isAttribution = val),
                              onSelectedCategoryChanged: (val) => setState(() => _selectedCategory = val),
                              onNavigateToNote: _navigateToNote,
                            ),
                          ),
                        ],
                      )
                    : _buildEditor(theme, showCategoryDropdown: true, categories: provider.categories),
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildEditor(WriterTheme theme, {bool showCategoryDropdown = false, List<String>? categories}) {
    if (_isAttribution) {
      final provider = context.read<NotesProvider>();
      final availableNotes = provider.cards.where((c) => !c.isAttribution).toList();
      return NoteEditorAttributionList(
        titleController: _titleController,
        items: _attributionItems,
        attributionType: _attributionType,
        availableNotes: availableNotes,
        theme: theme,
        onTypeChanged: (type) {
          setState(() {
            _attributionType = type;
          });
          _saveCurrentNoteState();
        },
        onItemTextChanged: (index, text) {
          setState(() {
            _attributionItems[index] = _attributionItems[index].copyWith(text: text);
          });
          _saveCurrentNoteState();
        },
        onItemAdded: (index, text) {
          setState(() {
            if (index == -1) {
              _attributionItems.add(AttributionItem(text: text));
            } else {
              _attributionItems.insert(index + 1, AttributionItem(text: text));
            }
          });
          _saveCurrentNoteState();
        },
        onItemDeleted: _deleteAttributionItem,
        onLinkNote: _linkNoteToItem,
        onUnlinkNote: _unlinkNoteFromItem,
        onNavigateToNote: _navigateToNote,
      );
    } else {
      return NoteEditorStandardField(
        titleController: _titleController,
        contentController: _contentController,
        theme: theme,
        showCategoryDropdown: showCategoryDropdown,
        categories: categories,
        selectedCategory: _selectedCategory,
        onSelectedCategoryChanged: (val) {
          setState(() => _selectedCategory = val);
        },
        isAttribution: _isAttribution,
        sourceUrl: _sourceUrlController.text,
      );
    }
  }
}
