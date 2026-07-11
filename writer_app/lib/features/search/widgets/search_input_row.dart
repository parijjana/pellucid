import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';
import '../providers/search_provider.dart';

/// The palette's top row: search icon, query field, match counter, prev/next
/// navigation, the replace-row reveal chevron (Ghost aesthetic: dim idle,
/// brightens when the replace row is open), and the close button.
class SearchInputRow extends StatelessWidget {
  final WriterTheme theme;
  final SearchProvider searchProvider;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;
  final VoidCallback onToggleReplace;

  const SearchInputRow({
    super.key,
    required this.theme,
    required this.searchProvider,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onToggleReplace,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = searchProvider.query.isNotEmpty;

    return Row(
      children: [
        IconButton(
          key: const Key('search_replace_toggle'),
          icon: Icon(
            searchProvider.replaceMode ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: theme.foregroundColor.withValues(alpha: searchProvider.replaceMode ? 0.5 : 0.2),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: onToggleReplace,
          tooltip: 'Toggle Replace',
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.search,
          size: 20,
          color: theme.foregroundColor.withValues(alpha: 0.3),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: const Key('search_query_field'),
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (_) => onSubmitted(),
            style: TextStyle(
              color: theme.foregroundColor,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Search manuscript, notes, and chapters...',
              hintStyle: TextStyle(
                color: theme.foregroundColor.withValues(alpha: 0.25),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (hasQuery) ...[
          Text(
            '${searchProvider.matchOffsets.isEmpty ? 0 : searchProvider.currentMatchIndex + 1} of ${searchProvider.matchOffsets.length}',
            style: TextStyle(
              color: theme.foregroundColor.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              Icons.keyboard_arrow_up,
              size: 18,
              color: theme.foregroundColor.withValues(alpha: 0.5),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: searchProvider.previousMatch,
            tooltip: 'Previous Match',
          ),
          IconButton(
            icon: Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: theme.foregroundColor.withValues(alpha: 0.5),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: searchProvider.nextMatch,
            tooltip: 'Next Match',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 16,
              color: theme.foregroundColor.withValues(alpha: 0.4),
            ),
            onPressed: controller.clear,
          ),
        ] else
          IconButton(
            icon: Icon(
              Icons.close,
              size: 16,
              color: theme.foregroundColor.withValues(alpha: 0.4),
            ),
            onPressed: () => searchProvider.toggleSearch(isOpen: false),
          ),
      ],
    );
  }
}
