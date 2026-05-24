// @trace FEAT-20260522-0001
// Description: Dual-mode note editor dialog (Popup and Fullscreen overlay).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/note_card.dart';
import '../providers/notes_provider.dart';
import '../providers/note_editor_controller.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';
import 'note_editor_power_panel.dart';
import 'note_editor_standard_field.dart';
import 'note_editor_attribution_list.dart';
import 'note_editor_top_bar.dart';
import '../../editor/widgets/shortcuts.dart';

class NoteEditorDialog extends StatefulWidget {
  final String noteId;

  const NoteEditorDialog({super.key, required this.noteId});

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  late final NoteEditorController _controller;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _controller = NoteEditorController(
      currentNoteId: widget.noteId,
      initialFullScreen: settings.lastNotesFullscreenState,
    );

    final notesProvider = context.read<NotesProvider>();
    _controller.init(notesProvider);

    _controller.addListener(_handleControllerUpdate);

    // Save initial state (if we auto-created the first item) after the build frame finishes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cardIndex = notesProvider.cards.indexWhere((c) => c.id == widget.noteId);
      if (cardIndex != -1) {
        final card = notesProvider.cards[cardIndex];
        if (card.isAttribution && (card.attributionItems == null || card.attributionItems!.isEmpty)) {
          final sync = context.read<SyncProvider>();
          final editor = context.read<EditorProvider>();
          _controller.saveCurrentNoteState(
            provider: notesProvider,
            sync: sync,
            editor: editor,
            settings: settings,
          );
        }
      }
    });
  }

  void _handleControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _saveCurrentNoteState() {
    final notes = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    _controller.saveCurrentNoteState(
      provider: notes,
      sync: sync,
      editor: editor,
      settings: settings,
    );
  }

  void _navigateToNote(String nextNoteId) {
    final notes = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    _controller.navigateToNote(nextNoteId, notes, sync, editor, settings);
  }

  void _goBack() {
    final notes = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    _controller.goBack(notes, sync, editor, settings);
  }

  void _cycleCategory() {
    final notes = context.read<NotesProvider>();
    _controller.cycleCategory(notes);
  }

  void _linkNoteToItem(int index, String targetNoteId) {
    final notes = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    _controller.linkNoteToItem(index, targetNoteId, notes, sync, editor, settings);
  }

  void _unlinkNoteFromItem(int index, String targetNoteId) {
    final notes = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    _controller.unlinkNoteFromItem(index, targetNoteId, notes, sync, editor, settings);
  }

  void _deleteAttributionItem(int index) {
    final notes = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    _controller.deleteAttributionItem(index, notes, sync, editor, settings);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final provider = context.watch<NotesProvider>();
    final settings = context.watch<SettingsProvider>();

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    final double width = _controller.isFullScreen ? screenWidth : screenWidth * 0.7;
    final double height = _controller.isFullScreen ? screenHeight : screenHeight * 0.5;

    final currentCardIndex = provider.cards.indexWhere((c) => c.id == _controller.currentNoteId);
    final currentCard = currentCardIndex != -1 ? provider.cards[currentCardIndex] : null;

    if (currentCard == null) {
      return const SizedBox.shrink();
    }

    return Dialog(
      constraints: BoxConstraints.tightFor(width: width, height: height),
      insetPadding: _controller.isFullScreen ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      backgroundColor: Colors.transparent,
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenAttributionIntent: CallbackAction<OpenAttributionIntent>(
            onInvoke: (intent) {
              _saveCurrentNoteState();
              Navigator.pop(context);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              final isAlt = HardwareKeyboard.instance.isAltPressed;
              final isMeta = HardwareKeyboard.instance.isMetaPressed;
              final isControl = HardwareKeyboard.instance.isControlPressed;
              final bool isMac = Platform.isMacOS;
  
              // Alt + B (existing)
              if (isAlt && event.logicalKey == LogicalKeyboardKey.keyB) {
                _saveCurrentNoteState();
                Navigator.pop(context);
                return KeyEventResult.handled;
              }
  
              // Alt + A (Windows/Linux) or Cmd + Ctrl + A (macOS)
              final bool matchA = isMac
                  ? (isMeta && isControl && event.logicalKey == LogicalKeyboardKey.keyA)
                  : (isAlt && event.logicalKey == LogicalKeyboardKey.keyA);
              if (matchA) {
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
              borderRadius: _controller.isFullScreen ? BorderRadius.zero : BorderRadius.circular(16),
              boxShadow: theme.sidebarShadows,
            ),
            child: Column(
              children: [
                NoteEditorTopBar(
                  theme: theme,
                  isAttribution: _controller.isAttribution,
                  isFullScreen: _controller.isFullScreen,
                  showBackButton: _controller.navigationHistory.isNotEmpty,
                  onBackPressed: _goBack,
                  onToggleFullScreen: () {
                    _controller.setFullScreen(!_controller.isFullScreen);
                    settings.setLastNotesFullscreenState(_controller.isFullScreen);
                  },
                  onClosePressed: () {
                    _saveCurrentNoteState();
                    Navigator.pop(context);
                  },
                ),
                Expanded(
                  child: _controller.isFullScreen
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
                                isAttribution: _controller.isAttribution,
                                sourceUrlController: _controller.sourceUrlController,
                                newCategoryController: _controller.newCategoryController,
                                selectedCategory: _controller.selectedCategory,
                                onIsAttributionChanged: (val) => _controller.setIsAttribution(val),
                                onSelectedCategoryChanged: (val) => _controller.setSelectedCategory(val),
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
      ),
    );
  }

  Widget _buildEditor(WriterTheme theme, {bool showCategoryDropdown = false, List<String>? categories}) {
    if (_controller.isAttribution) {
      final provider = context.read<NotesProvider>();
      final availableNotes = provider.cards.where((c) => !c.isAttribution).toList();
      return NoteEditorAttributionList(
        titleController: _controller.titleController,
        items: _controller.attributionItems,
        attributionType: _controller.attributionType,
        availableNotes: availableNotes,
        theme: theme,
        onTypeChanged: (type) {
          final notes = context.read<NotesProvider>();
          final sync = context.read<SyncProvider>();
          final editor = context.read<EditorProvider>();
          final settings = context.read<SettingsProvider>();
          _controller.updateAttributionType(type, notes, sync, editor, settings);
        },
        onItemTextChanged: (index, text) {
          final notes = context.read<NotesProvider>();
          final sync = context.read<SyncProvider>();
          final editor = context.read<EditorProvider>();
          final settings = context.read<SettingsProvider>();
          _controller.updateAttributionItemText(index, text, notes, sync, editor, settings);
        },
        onItemAdded: (index, text) {
          final notes = context.read<NotesProvider>();
          final sync = context.read<SyncProvider>();
          final editor = context.read<EditorProvider>();
          final settings = context.read<SettingsProvider>();
          _controller.addAttributionItem(index, text, notes, sync, editor, settings);
        },
        onItemDeleted: _deleteAttributionItem,
        onLinkNote: _linkNoteToItem,
        onUnlinkNote: _unlinkNoteFromItem,
        onNavigateToNote: _navigateToNote,
      );
    } else {
      return NoteEditorStandardField(
        titleController: _controller.titleController,
        contentController: _controller.contentController,
        theme: theme,
        showCategoryDropdown: showCategoryDropdown,
        categories: categories,
        selectedCategory: _controller.selectedCategory,
        onSelectedCategoryChanged: (val) {
          _controller.setSelectedCategory(val);
        },
        isAttribution: _controller.isAttribution,
        sourceUrl: _controller.sourceUrlController.text,
      );
    }
  }
}
