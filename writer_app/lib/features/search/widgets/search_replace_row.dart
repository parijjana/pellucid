import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';
import '../providers/search_provider.dart';

/// The palette's second row, revealed by the chevron in [SearchInputRow]:
/// a replacement-text field plus Replace (current match) / Replace All
/// actions. Matching mirrors search exactly (case-insensitive substring) —
/// there is no match-case/whole-word toggle in v1.
class SearchReplaceRow extends StatelessWidget {
  final WriterTheme theme;
  final SearchProvider searchProvider;
  final TextEditingController controller;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;

  const SearchReplaceRow({
    super.key,
    required this.theme,
    required this.searchProvider,
    required this.controller,
    required this.onReplace,
    required this.onReplaceAll,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasMatches = searchProvider.matchOffsets.isNotEmpty;
    final ButtonStyle ghostButtonStyle = TextButton.styleFrom(
      foregroundColor: theme.foregroundColor.withValues(alpha: hasMatches ? 0.6 : 0.2),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Row(
      children: [
        Icon(
          Icons.find_replace,
          size: 18,
          color: theme.foregroundColor.withValues(alpha: 0.3),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: const Key('search_replace_field'),
            controller: controller,
            style: TextStyle(
              color: theme.foregroundColor,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Replace with...',
              hintStyle: TextStyle(
                color: theme.foregroundColor.withValues(alpha: 0.25),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        TextButton(
          key: const Key('search_replace_one_button'),
          style: ghostButtonStyle,
          onPressed: hasMatches ? onReplace : null,
          child: const Text('Replace'),
        ),
        TextButton(
          key: const Key('search_replace_all_button'),
          style: ghostButtonStyle,
          onPressed: hasMatches ? onReplaceAll : null,
          child: const Text('Replace All'),
        ),
      ],
    );
  }
}
