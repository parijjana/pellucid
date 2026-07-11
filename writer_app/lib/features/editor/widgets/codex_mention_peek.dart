// @trace FEAT-20260705-CODEX-0002
// Description: Floating "peek" card shown when hovering a recognised Codex
// mention in the manuscript — title + a short content excerpt, ghost aesthetic.

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class CodexMentionPeek extends StatelessWidget {
  final WriterTheme theme;
  final String title;
  final String content;

  const CodexMentionPeek({
    super.key,
    required this.theme,
    required this.title,
    required this.content,
  });

  static const int _excerptLength = 160;

  String get _excerpt {
    final collapsed = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return 'No details yet.';
    if (collapsed.length <= _excerptLength) return collapsed;
    return '${collapsed.substring(0, _excerptLength).trimRight()}…';
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = theme.foregroundColor;
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.sidebarColor.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: fg.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _excerpt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg.withValues(alpha: 0.55),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
