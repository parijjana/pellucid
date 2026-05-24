// @trace FEAT-20260516-120000-0001
// Description: Compact card representation for the sidebar (Categorized).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/note_card.dart';
import '../providers/notes_provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';

class NoteMiniCard extends StatelessWidget {
  final NoteCard card;
  final WriterTheme theme;
  final VoidCallback onTap;
  final bool isHighlighted;

  const NoteMiniCard({
    super.key,
    required this.card,
    required this.theme,
    required this.onTap,
    this.isHighlighted = false,
  });

  Color _getCategoryColor() {
    switch (card.category) {
      case 'people':
        return Colors.blue.withValues(alpha: 0.1);
      case 'places':
        return Colors.green.withValues(alpha: 0.1);
      case 'events':
        return Colors.orange.withValues(alpha: 0.1);
      case 'general':
        return theme.foregroundColor.withValues(alpha: 0.05);
      default:
        final int hash = card.category.hashCode.abs();
        final Color baseColor = Colors.primaries[hash % Colors.primaries.length];
        return baseColor.withValues(alpha: 0.1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: _getCategoryColor(),
          borderRadius: BorderRadius.circular(12),
          boxShadow: theme.sidebarShadows,
          border: Border.all(
            color: isHighlighted ? theme.foregroundColor.withValues(alpha: 0.6) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (card.title.isNotEmpty)
                  Expanded(
                    child: Text(
                      card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.foregroundColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 14, color: theme.foregroundColor.withValues(alpha: 0.2)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (val) {
                    if (val == 'delete') {
                      final sync = context.read<SyncProvider>();
                      final wasAttribution = card.isAttribution;
                      context.read<NotesProvider>().deleteCard(card.id, syncProvider: sync);
                      if (wasAttribution) {
                        final settings = context.read<SettingsProvider>();
                        context.read<EditorProvider>().syncAttributions(
                          null,
                          syncProvider: sync,
                          projectName: settings.currentProjectName,
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Note', style: TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
            if (card.title.isNotEmpty) const SizedBox(height: 4),
            Text(
              card.isAttribution ? card.getAttributionMarkdown() : card.content,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.foregroundColor.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
