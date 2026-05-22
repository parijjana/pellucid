import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/note_card.dart';
import '../../editor/providers/theme_provider.dart';

class NoteEditorAttributionListItem extends StatelessWidget {
  final AttributionItem item;
  final int index;
  final String prefix;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<NoteCard> availableNotes;
  final WriterTheme theme;
  final Function(int index, String text) onItemTextChanged;
  final ValueChanged<int> onItemDeleted;
  final Function(int index, String targetNoteId) onLinkNote;
  final Function(int index, String targetNoteId) onUnlinkNote;
  final ValueChanged<String> onNavigateToNote;

  const NoteEditorAttributionListItem({
    super.key,
    required this.item,
    required this.index,
    required this.prefix,
    required this.controller,
    required this.focusNode,
    required this.availableNotes,
    required this.theme,
    required this.onItemTextChanged,
    required this.onItemDeleted,
    required this.onLinkNote,
    required this.onUnlinkNote,
    required this.onNavigateToNote,
  });

  String? _extractUrl(String text) {
    final match = RegExp(r'(https?://[^\s]+|www\.[^\s]+)').firstMatch(text);
    if (match == null) return null;
    var url = match.group(0)!;
    // If it starts with www., prepend https:// so canLaunchUrl / launchUrl can open it
    if (url.startsWith('www.')) {
      url = 'https://$url';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final textUrl = _extractUrl(item.text);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8.0, right: 12.0),
                child: Text(
                  prefix,
                  style: TextStyle(
                    color: theme.foregroundColor.withValues(alpha: 0.6),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(
                    color: theme.foregroundColor.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter attribution details...',
                    hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (text) => onItemTextChanged(index, text),
                ),
              ),
              if (textUrl != null)
                IconButton(
                  icon: Icon(Icons.open_in_new, size: 16, color: theme.foregroundColor.withValues(alpha: 0.6)),
                  onPressed: () async {
                    final uri = Uri.tryParse(textUrl);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  tooltip: 'Open link',
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.link, size: 16, color: theme.foregroundColor.withValues(alpha: 0.4)),
                tooltip: 'Link to research note',
                onSelected: (noteId) {
                  if (item.connections.contains(noteId)) {
                    onUnlinkNote(index, noteId);
                  } else {
                    onLinkNote(index, noteId);
                  }
                },
                itemBuilder: (context) {
                  if (availableNotes.isEmpty) {
                    return [
                      const PopupMenuItem(
                        enabled: false,
                        child: Text('No research notes available', style: TextStyle(fontSize: 12)),
                      ),
                    ];
                  }
                  return availableNotes.map((note) {
                    final isLinked = item.connections.contains(note.id);
                    return PopupMenuItem<String>(
                      value: note.id,
                      child: Row(
                        children: [
                          Icon(
                            isLinked ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 16,
                            color: theme.foregroundColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              note.title.isEmpty ? 'Untitled' : note.title,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.withValues(alpha: 0.6)),
                onPressed: () => onItemDeleted(index),
                tooltip: 'Delete item',
              ),
            ],
          ),
          if (item.connections.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 24.0, top: 4.0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.connections.map((noteId) {
                  final note = availableNotes.firstWhere(
                    (n) => n.id == noteId,
                    orElse: () => NoteCard(title: 'Deleted Note', content: ''),
                  );
                  return InputChip(
                    label: Text('#${note.title.isEmpty ? "Untitled" : note.title}'),
                    labelStyle: TextStyle(color: theme.foregroundColor, fontSize: 10),
                    backgroundColor: theme.foregroundColor.withValues(alpha: 0.05),
                    onPressed: note.id == 'Deleted Note' ? null : () => onNavigateToNote(noteId),
                    onDeleted: () => onUnlinkNote(index, noteId),
                    deleteIconColor: theme.foregroundColor.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
