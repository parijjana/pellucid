// @trace FEAT-20260522-0001
// Description: Sidebar interface showing the notes list and handling creation & edit triggers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/shortcuts_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/note_card.dart';
import '../widgets/note_mini_card.dart';
import '../widgets/note_editor_dialog.dart';
import '../../sync/providers/sync_provider.dart';
import '../../editor/widgets/shortcuts.dart';
import '../../editor/providers/editor_provider.dart';
import '../../settings/providers/settings_provider.dart';

class NotesSidebar extends StatefulWidget {
  const NotesSidebar({super.key});

  @override
  State<NotesSidebar> createState() => _NotesSidebarState();
}

class _NotesSidebarState extends State<NotesSidebar> {
  late FocusNode _sidebarFocusNode;
  int _highlightedIndex = -1;
  bool _wasOpen = false;

  @override
  void initState() {
    super.initState();
    _sidebarFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _sidebarFocusNode.dispose();
    super.dispose();
  }

  void _createNewNoteAndEdit(BuildContext context, NotesProvider provider) {
    final sync = context.read<SyncProvider>();
    provider.addCard(category: 'general', syncProvider: sync);
    final newNoteId = provider.cards.last.id;
    showDialog(
      context: context,
      builder: (context) => NoteEditorDialog(noteId: newNoteId),
    );
  }

  void _createAttributionNote(BuildContext context, NotesProvider provider) {
    final sync = context.read<SyncProvider>();
    provider.addAttributionCard(syncProvider: sync);
    final attributionCard = provider.cards.cast<NoteCard?>().firstWhere(
      (c) => c!.isAttribution,
      orElse: () => null,
    );

    if (attributionCard != null) {
      // Sync to manuscript
      final editor = context.read<EditorProvider>();
      final settings = context.read<SettingsProvider>();
      editor.syncAttributions(attributionCard, syncProvider: sync, projectName: settings.currentProjectName);

      showDialog(
        context: context,
        builder: (context) => NoteEditorDialog(noteId: attributionCard.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final notesProvider = context.watch<NotesProvider>();
    final normalCards = notesProvider.cards.where((c) => !c.isAttribution).toList();
    final attributionCard = notesProvider.cards.cast<NoteCard?>().firstWhere(
      (c) => c!.isAttribution,
      orElse: () => null,
    );

    final isRightSidebarOpen = context.watch<ShortcutsProvider>().isRightSidebarOpen;
    if (isRightSidebarOpen && !_wasOpen) {
      _wasOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sidebarFocusNode.requestFocus();
      });
    } else if (!isRightSidebarOpen) {
      _wasOpen = false;
    }

    if (_highlightedIndex > normalCards.length) {
      _highlightedIndex = normalCards.length;
    }

    return Focus(
      focusNode: _sidebarFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() {
              if (normalCards.isEmpty) {
                _highlightedIndex = 0;
              } else {
                _highlightedIndex = (_highlightedIndex + 1) % (normalCards.length + 1);
              }
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            setState(() {
              if (normalCards.isEmpty) {
                _highlightedIndex = 0;
              } else {
                _highlightedIndex = (_highlightedIndex - 1 + normalCards.length + 1) % (normalCards.length + 1);
              }
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (_highlightedIndex >= 0 && _highlightedIndex < normalCards.length) {
              final card = normalCards[_highlightedIndex];
              showDialog(
                context: context,
                builder: (context) => NoteEditorDialog(noteId: card.id),
              );
              return KeyEventResult.handled;
            } else if (_highlightedIndex == normalCards.length) {
              if (attributionCard == null) {
                _createAttributionNote(context, notesProvider);
              } else {
                showDialog(
                  context: context,
                  builder: (context) => NoteEditorDialog(noteId: attributionCard.id),
                );
              }
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          AddNoteIntent: CallbackAction<AddNoteIntent>(onInvoke: (_) {
            _createNewNoteAndEdit(context, notesProvider);
            return null;
          }),
        },
        child: Container(
          color: theme.sidebarColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'NOTES & RESEARCH',
                      style: TextStyle(
                        color: theme.foregroundColor.withValues(alpha: 0.2),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.2,
                      ),
                    ),
                    _GhostIconButton(
                      icon: Icons.add,
                      onPressed: () => _createNewNoteAndEdit(context, notesProvider),
                      theme: theme,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: normalCards.length,
                  itemBuilder: (context, index) {
                    final card = normalCards[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: NoteMiniCard(
                        card: card,
                        theme: theme,
                        isHighlighted: _highlightedIndex == index,
                        onTap: () {
                          setState(() {
                            _highlightedIndex = index;
                          });
                          showDialog(
                            context: context,
                            builder: (context) => NoteEditorDialog(noteId: card.id),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: AttributionsTextButton(
                  isHighlighted: _highlightedIndex == normalCards.length,
                  onTap: () {
                    setState(() {
                      _highlightedIndex = normalCards.length;
                    });
                    if (attributionCard == null) {
                      _createAttributionNote(context, notesProvider);
                    } else {
                      showDialog(
                        context: context,
                        builder: (context) => NoteEditorDialog(noteId: attributionCard.id),
                      );
                    }
                  },
                  theme: theme,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final WriterTheme theme;

  const _GhostIconButton({required this.icon, required this.onPressed, required this.theme});

  @override
  State<_GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<_GhostIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isHovered ? 1.0 : 0.2,
        child: IconButton(
          icon: Icon(widget.icon, size: 16, color: widget.theme.foregroundColor),
          onPressed: widget.onPressed,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class AttributionsTextButton extends StatefulWidget {
  final VoidCallback onTap;
  final WriterTheme theme;
  final bool isHighlighted;

  const AttributionsTextButton({
    super.key,
    required this.onTap,
    required this.theme,
    this.isHighlighted = false,
  });

  @override
  State<AttributionsTextButton> createState() => _AttributionsTextButtonState();
}

class _AttributionsTextButtonState extends State<AttributionsTextButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _isHovered || widget.isHighlighted;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.0),
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.isHighlighted ? widget.theme.foregroundColor.withValues(alpha: 0.6) : Colors.transparent,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: active ? 1.0 : 0.4,
            child: Text(
              'Attributions',
              style: TextStyle(
                color: widget.theme.foregroundColor,
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                decoration: active ? TextDecoration.underline : TextDecoration.none,
                decorationColor: widget.theme.foregroundColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

