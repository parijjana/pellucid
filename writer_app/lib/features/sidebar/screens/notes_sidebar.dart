import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/note_card.dart';
import '../widgets/note_mini_card.dart';
import '../../sync/providers/sync_provider.dart';
import '../../editor/widgets/shortcuts.dart';

class NotesSidebar extends StatefulWidget {
  const NotesSidebar({super.key});

  @override
  State<NotesSidebar> createState() => _NotesSidebarState();
}

class _NotesSidebarState extends State<NotesSidebar> {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final notesProvider = context.watch<NotesProvider>();

    return Actions(
      actions: <Type, Action<Intent>>{
        AddNoteIntent: CallbackAction<AddNoteIntent>(onInvoke: (_) {
          _showAddNoteDialog(context, notesProvider, theme);
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
                    onPressed: () => _showAddNoteDialog(context, notesProvider, theme),
                    theme: theme,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: notesProvider.cards.length,
                itemBuilder: (context, index) {
                  final card = notesProvider.cards[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NoteMiniCard(
                      card: card,
                      theme: theme,
                      onTap: () {
                        // Logic to view/edit note
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddNoteDialog(BuildContext context, NotesProvider provider, WriterTheme theme) {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    NoteCategory selectedCategory = NoteCategory.general;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Actions(
          actions: <Type, Action<Intent>>{
            SaveNoteIntent: CallbackAction<SaveNoteIntent>(onInvoke: (_) {
              _handleSave(context, provider, titleController, contentController, selectedCategory);
              return null;
            }),
            CycleNoteCategoryIntent: CallbackAction<CycleNoteCategoryIntent>(onInvoke: (_) {
              setDialogState(() {
                final categories = NoteCategory.values;
                final currentIndex = categories.indexOf(selectedCategory);
                selectedCategory = categories[(currentIndex + 1) % categories.length];
              });
              return null;
            }),
          },
          child: AlertDialog(
            backgroundColor: theme.sidebarColor,
            title: Text('New Research Note', style: TextStyle(color: theme.foregroundColor)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  style: TextStyle(color: theme.foregroundColor),
                  decoration: InputDecoration(
                    hintText: 'Title (Alt+B to Save)',
                    hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  maxLines: 5,
                  style: TextStyle(color: theme.foregroundColor),
                  decoration: InputDecoration(
                    hintText: 'Content...',
                    hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2)),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButton<NoteCategory>(
                  value: selectedCategory,
                  dropdownColor: theme.sidebarColor,
                  isExpanded: true,
                  items: NoteCategory.values.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(category.name.toUpperCase(), style: TextStyle(color: theme.foregroundColor, fontSize: 12)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedCategory = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () => _handleSave(context, provider, titleController, contentController, selectedCategory),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSave(BuildContext context, NotesProvider provider, TextEditingController title, TextEditingController content, NoteCategory category) {
    if (title.text.isNotEmpty) {
      final sync = context.read<SyncProvider>();
      provider.addCard(category: category, syncProvider: sync);
      final newId = provider.cards.last.id;
      provider.updateCard(
        newId, 
        title: title.text, 
        content: content.text, 
        category: category,
        syncProvider: sync,
      );
      Navigator.pop(context);
    }
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
