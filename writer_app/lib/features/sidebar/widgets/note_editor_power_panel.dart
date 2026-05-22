// @trace FEAT-20260522-0001
// Description: Right sidebar panel for power features in NoteEditorDialog.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/note_card.dart';
import '../providers/notes_provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../sync/providers/sync_provider.dart';

class NoteEditorPowerPanel extends StatelessWidget {
  final WriterTheme theme;
  final NotesProvider provider;
  final NoteCard currentCard;
  final bool isAttribution;
  final TextEditingController sourceUrlController;
  final TextEditingController newCategoryController;
  final String selectedCategory;
  final ValueChanged<bool> onIsAttributionChanged;
  final ValueChanged<String> onSelectedCategoryChanged;
  final ValueChanged<String> onNavigateToNote;

  const NoteEditorPowerPanel({
    super.key,
    required this.theme,
    required this.provider,
    required this.currentCard,
    required this.isAttribution,
    required this.sourceUrlController,
    required this.newCategoryController,
    required this.selectedCategory,
    required this.onIsAttributionChanged,
    required this.onSelectedCategoryChanged,
    required this.onNavigateToNote,
  });

  @override
  Widget build(BuildContext context) {
    final connectedCards = provider.cards.where((c) => currentCard.connections.contains(c.id)).toList();

    // Group available cards by category
    final Map<String, List<NoteCard>> categorizedNotes = {};
    for (var cat in provider.categories) {
      categorizedNotes[cat] = [];
    }
    for (var c in provider.cards) {
      if (c.id == currentCard.id) continue;
      if (currentCard.connections.contains(c.id)) continue;

      if (!categorizedNotes.containsKey(c.category)) {
        categorizedNotes[c.category] = [];
      }
      categorizedNotes[c.category]!.add(c);
    }

    return ListView(
      padding: const EdgeInsets.all(20.0),
      children: [
        // Category Selection
        Text(
          'CATEGORY',
          style: TextStyle(
            color: theme.foregroundColor.withValues(alpha: 0.4),
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: provider.categories.contains(selectedCategory) ? selectedCategory : 'general',
          dropdownColor: theme.sidebarColor,
          isExpanded: true,
          style: TextStyle(color: theme.foregroundColor, fontSize: 13),
          underline: Container(height: 1, color: theme.foregroundColor.withValues(alpha: 0.1)),
          items: provider.categories.map((cat) {
            return DropdownMenuItem(
              value: cat,
              child: Text(cat.toUpperCase()),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              onSelectedCategoryChanged(val);
            }
          },
        ),
        const SizedBox(height: 24),

        // Attribution Toggle & Url
        if (!currentCard.isAttribution && !provider.cards.any((c) => c.isAttribution)) ...[
          Text(
            'ATTRIBUTION',
            style: TextStyle(
              color: theme.foregroundColor.withValues(alpha: 0.4),
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('Mark as Attribution', style: TextStyle(color: theme.foregroundColor, fontSize: 13)),
              ),
              Switch(
                value: isAttribution,
                activeThumbColor: theme.foregroundColor,
                onChanged: onIsAttributionChanged,
              ),
            ],
          ),
        ],
        if (isAttribution) ...[
          if (currentCard.isAttribution || provider.cards.any((c) => c.isAttribution)) ...[
            Text(
              'ATTRIBUTION SOURCE',
              style: TextStyle(
                color: theme.foregroundColor.withValues(alpha: 0.4),
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 1.0,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: sourceUrlController,
            style: TextStyle(color: theme.foregroundColor, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Source URL (e.g. https://...)',
              hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.1))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor)),
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Custom Category Creator
        Text(
          'CREATE CUSTOM CATEGORY',
          style: TextStyle(
            color: theme.foregroundColor.withValues(alpha: 0.4),
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: newCategoryController,
                style: TextStyle(color: theme.foregroundColor, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'New category name...',
                  hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.1))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.add, color: theme.foregroundColor, size: 20),
              onPressed: () async {
                final newCat = newCategoryController.text.trim();
                if (newCat.isNotEmpty) {
                  await provider.addCategory(newCat);
                  onSelectedCategoryChanged(newCat.toLowerCase());
                  newCategoryController.clear();
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Connected Notes
        Text(
          'CONNECTED NOTES',
          style: TextStyle(
            color: theme.foregroundColor.withValues(alpha: 0.4),
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        if (connectedCards.isEmpty)
          Text(
            'No connected notes. Use hashtags below to link notes.',
            style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.3), fontSize: 11, fontStyle: FontStyle.italic),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: connectedCards.map((cc) {
              return InputChip(
                label: Text('#${cc.title.isEmpty ? "Untitled" : cc.title}'),
                labelStyle: TextStyle(color: theme.foregroundColor, fontSize: 11),
                backgroundColor: theme.foregroundColor.withValues(alpha: 0.05),
                onPressed: () => onNavigateToNote(cc.id),
                onDeleted: () {
                  final sync = context.read<SyncProvider>();
                  provider.disconnectCards(currentCard.id, cc.id, syncProvider: sync);
                },
                deleteIconColor: theme.foregroundColor.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              );
            }).toList(),
          ),
        const SizedBox(height: 24),

        // Available Notes to Link Grouped by Category
        Text(
          'LINK AVAILABLE NOTES',
          style: TextStyle(
            color: theme.foregroundColor.withValues(alpha: 0.4),
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        ...categorizedNotes.entries.map((entry) {
          final cat = entry.key;
          final notes = entry.value;
          if (notes.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: Text(
                  cat.toUpperCase(),
                  style: TextStyle(
                    color: theme.foregroundColor.withValues(alpha: 0.3),
                    fontWeight: FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: notes.map((n) {
                  return ActionChip(
                    label: Text('#${n.title.isEmpty ? "Untitled" : n.title}'),
                    labelStyle: TextStyle(color: theme.foregroundColor, fontSize: 11),
                    backgroundColor: theme.foregroundColor.withValues(alpha: 0.02),
                    onPressed: () {
                      final sync = context.read<SyncProvider>();
                      provider.connectCards(currentCard.id, n.id, syncProvider: sync);
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  );
                }).toList(),
              ),
            ],
          );
        }),
      ],
    );
  }
}
