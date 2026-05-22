// @trace FEAT-20260522-0001
// Description: Sidebar interface showing the notes list and handling creation & edit triggers.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
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
    final attributionCard = provider.cards.firstWhere((c) => c.isAttribution);

    // Sync to manuscript
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    editor.syncAttributions(attributionCard, syncProvider: sync, projectName: settings.currentProjectName);

    showDialog(
      context: context,
      builder: (context) => NoteEditorDialog(noteId: attributionCard.id),
    );
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

    return Actions(
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
                      onTap: () {
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
              child: _AttributionsTextButton(
                onTap: () {
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

class _AttributionsTextButton extends StatefulWidget {
  final VoidCallback onTap;
  final WriterTheme theme;

  const _AttributionsTextButton({
    required this.onTap,
    required this.theme,
  });

  @override
  State<_AttributionsTextButton> createState() => _AttributionsTextButtonState();
}

class _AttributionsTextButtonState extends State<_AttributionsTextButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isHovered ? 0.8 : 0.4,
            child: Text(
              'Attributions',
              style: TextStyle(
                color: widget.theme.foregroundColor,
                fontSize: 13,
                decoration: _isHovered ? TextDecoration.underline : TextDecoration.none,
                decorationColor: widget.theme.foregroundColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

