import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
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

  List<InlineSpan> _highlightText(String text, TextStyle baseStyle, String query) {
    if (query.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }
    
    final List<InlineSpan> spans = [];
    final escaped = RegExp.escape(query);
    final regex = RegExp(escaped, caseSensitive: false);
    
    int lastEnd = 0;
    final matches = regex.allMatches(text);
    
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }
      
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: baseStyle.copyWith(
          backgroundColor: Colors.amber.withValues(alpha: 0.35),
        ),
      ));
      lastEnd = match.end;
    }
    
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }
    
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final searchProvider = context.watch<SearchProvider>();
    final searchQuery = searchProvider.query;

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
                    return _sidebarItem(
                      h.title,
                      theme,
                      false,
                      searchQuery,
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
    String searchQuery, {
    int level = 1,
    VoidCallback? onTap,
  }) {
    final baseStyle = TextStyle(
      color: isActive ? theme.foregroundColor : theme.foregroundColor.withValues(alpha: 0.7),
      fontSize: 13.0 - (level - 1) * 1.0,
      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(left: 20.0 * level, right: 20, top: 12, bottom: 12),
        color: isActive ? theme.foregroundColor.withValues(alpha: 0.03) : Colors.transparent,
        child: RichText(
          text: TextSpan(
            children: _highlightText(label, baseStyle, searchQuery),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
