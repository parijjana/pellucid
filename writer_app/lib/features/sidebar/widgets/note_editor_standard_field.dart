import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../editor/providers/theme_provider.dart';

class NoteEditorStandardField extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController contentController;
  final WriterTheme theme;
  final bool showCategoryDropdown;
  final List<String>? categories;
  final String selectedCategory;
  final ValueChanged<String>? onSelectedCategoryChanged;
  final bool isAttribution;
  final String sourceUrl;

  const NoteEditorStandardField({
    super.key,
    required this.titleController,
    required this.contentController,
    required this.theme,
    this.showCategoryDropdown = false,
    this.categories,
    required this.selectedCategory,
    this.onSelectedCategoryChanged,
    required this.isAttribution,
    required this.sourceUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  style: TextStyle(
                    color: theme.foregroundColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Untitled Note',
                    hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2)),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (showCategoryDropdown && categories != null) ...[
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: categories!.contains(selectedCategory) ? selectedCategory : 'general',
                  dropdownColor: theme.sidebarColor,
                  style: TextStyle(color: theme.foregroundColor, fontSize: 12),
                  underline: const SizedBox(),
                  items: categories!.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat.toUpperCase(), style: const TextStyle(fontSize: 11)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null && onSelectedCategoryChanged != null) {
                      onSelectedCategoryChanged!(val);
                    }
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: contentController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: TextStyle(
                color: theme.foregroundColor.withValues(alpha: 0.9),
                fontSize: 14,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'Start typing thoughts, ideas, or references...',
                hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2)),
                border: InputBorder.none,
              ),
            ),
          ),
          if (isAttribution && sourceUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () async {
                  final trimmedUrl = sourceUrl.trim();
                  final uri = Uri.tryParse(trimmedUrl);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
                child: Row(
                  children: [
                    Icon(Icons.link, size: 14, color: theme.foregroundColor.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        sourceUrl.trim(),
                        style: TextStyle(
                          color: theme.foregroundColor.withValues(alpha: 0.6),
                          decoration: TextDecoration.underline,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
