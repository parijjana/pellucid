import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

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
    bool isActive, {
    int level = 1,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(left: 20.0 * level, right: 20, top: 12, bottom: 12),
        color: isActive ? theme.foregroundColor.withValues(alpha: 0.03) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? theme.foregroundColor : theme.foregroundColor.withValues(alpha: 0.4),
            fontSize: 13 - (level - 1) * 1.0,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
