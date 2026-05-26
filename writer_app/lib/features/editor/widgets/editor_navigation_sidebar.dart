import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/editor_provider.dart';
import '../../search/providers/search_provider.dart';

class EditorNavigationSidebar extends StatelessWidget {
  final WriterTheme theme;
  final List<({String title, int line, int level})> headers;
  final void Function(int) onHeaderTap;

  const EditorNavigationSidebar({
    super.key,
    required this.theme,
    required this.headers,
    required this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    final searchProvider = context.watch<SearchProvider>();
    final searchQuery = searchProvider.query;
    final editorContent = context.watch<EditorProvider>().content;

    final List<bool> headerMatches = [];
    if (searchQuery.isNotEmpty) {
      final docLines = editorContent.split('\n');
      for (int i = 0; i < headers.length; i++) {
        final startLine = headers[i].line;
        final endLine = (i < headers.length - 1) ? headers[i + 1].line - 1 : docLines.length - 1;
        
        bool hasMatch = false;
        if (startLine < docLines.length) {
          // Search in the body text of the chapter (excluding the header line itself)
          final bodyStart = startLine + 1;
          if (bodyStart <= endLine && bodyStart < docLines.length) {
            final chapterText = docLines.sublist(bodyStart, endLine + 1).join('\n');
            hasMatch = chapterText.toLowerCase().contains(searchQuery.toLowerCase());
          }
        }
        headerMatches.add(hasMatch);
      }
    } else {
      headerMatches.addAll(List.generate(headers.length, (_) => false));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            'TABLE OF CONTENTS',
            style: TextStyle(
              color: theme.foregroundColor.withValues(alpha: 0.2),
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: headers.isEmpty
              ? Center(
                  child: Text(
                    'No headers found',
                    style: TextStyle(
                      color: theme.foregroundColor.withValues(alpha: 0.2),
                      fontSize: 12,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: headers.length,
                  itemBuilder: (context, index) {
                    final h = headers[index];
                    final isMatch = headerMatches[index];
                    return _sidebarItem(
                      h.title,
                      theme,
                      false,
                      isMatch,
                      level: h.level,
                      onTap: () => onHeaderTap(h.line),
                    );
                  },
                ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _sidebarItem(
    String label,
    WriterTheme theme,
    bool isActive,
    bool isMatch, {
    int level = 1,
    VoidCallback? onTap,
  }) {
    final baseStyle = TextStyle(
      color: isActive 
          ? theme.foregroundColor 
          : (isMatch ? theme.foregroundColor : theme.foregroundColor.withValues(alpha: 0.7)),
      fontSize: 13.0 - (level - 1) * 1.0,
      fontWeight: (isActive || isMatch) ? FontWeight.w600 : FontWeight.w400,
    );

    Color getBgColor() {
      if (isActive) {
        return theme.foregroundColor.withValues(alpha: 0.06);
      }
      if (isMatch) {
        return Colors.amber.withValues(alpha: 0.15);
      }
      return Colors.transparent;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(left: 20.0 * level, right: 20, top: 12, bottom: 12),
        color: getBgColor(),
        child: Text(
          label,
          style: baseStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
