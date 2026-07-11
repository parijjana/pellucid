import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class CheatsheetOverlayContent extends StatelessWidget {
  final WriterTheme theme;

  const CheatsheetOverlayContent({
    super.key,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final bool isMac = !kIsWeb && Platform.isMacOS;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: theme.sidebarColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.1)),
              boxShadow: theme.sidebarShadows,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'KEYBOARD SHORTCUTS CHEATSHEET',
                  style: TextStyle(
                    color: theme.foregroundColor.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _CheatsheetItem(theme: theme, keys: 'Alt + 1', description: 'Toggle ToC'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + 2', description: 'Toggle Notes'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + 3', description: 'Toggle Toolbar'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + 4', description: 'Toggle Settings'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + 5', description: 'Typewriter Scrolling'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + 6', description: 'Paragraph Focus'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + Enter', description: 'Toggle Fullscreen'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + A', description: 'Attributions'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + Shift + A', description: 'Set Alarm'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + C', description: 'Peek Clock / Dismiss Alarm'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + S', description: 'Peek Session'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + P', description: 'Toggle Pomodoro'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + Shift + P', description: 'Reset Pomodoro'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + Shift + S', description: 'Toggle Sprint'),
                    _CheatsheetItem(theme: theme, keys: 'Alt + N', description: 'Add Note'),
                    _CheatsheetItem(theme: theme, keys: isMac ? 'Cmd + F' : 'Ctrl + F', description: 'Search'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheatsheetItem extends StatelessWidget {
  final WriterTheme theme;
  final String keys;
  final String description;

  const _CheatsheetItem({
    required this.theme,
    required this.keys,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: theme.foregroundColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            keys,
            style: TextStyle(
              color: theme.foregroundColor,
              fontSize: 10,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          description,
          style: TextStyle(
            color: theme.foregroundColor.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
