// @trace FEAT-20260522-0001
// Description: Stateless top bar widget for the note editor dialog.

import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';

class NoteEditorTopBar extends StatelessWidget {
  final WriterTheme theme;
  final bool isAttribution;
  final bool isFullScreen;
  final bool showBackButton;
  final VoidCallback onBackPressed;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onClosePressed;

  const NoteEditorTopBar({
    super.key,
    required this.theme,
    required this.isAttribution,
    required this.isFullScreen,
    required this.showBackButton,
    required this.onBackPressed,
    required this.onToggleFullScreen,
    required this.onClosePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (showBackButton)
                IconButton(
                  icon: Icon(Icons.arrow_back, color: theme.foregroundColor, size: 20),
                  onPressed: onBackPressed,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              if (showBackButton) const SizedBox(width: 8),
              Text(
                isAttribution ? 'ATTRIBUTION NOTE' : 'RESEARCH NOTE',
                style: TextStyle(
                  color: theme.foregroundColor.withValues(alpha: 0.4),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: theme.foregroundColor,
                  size: 20,
                ),
                onPressed: onToggleFullScreen,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: Icon(Icons.close, color: theme.foregroundColor, size: 20),
                onPressed: onClosePressed,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
