import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../../../core/platform_context.dart';

class CheatsheetOverlayContent extends StatelessWidget {
  final WriterTheme theme;

  const CheatsheetOverlayContent({
    super.key,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // "Uses Command as the primary shortcut modifier" — true on macOS AND
    // iOS/iPadOS. See usesCommandModifier in core/platform_context.dart.
    final bool isMac = usesCommandModifier;
    // macOS-*specifically* — the Ctrl+Cmd+F fullscreen convention below has
    // no iOS equivalent and stays gated on macOS alone (see main.dart).
    final bool isMacOSOnly = !kIsWeb && Platform.isMacOS;
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
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + 1', isMac), description: 'Toggle ToC'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + 2', isMac), description: 'Toggle Notes'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + 3', isMac), description: 'Toggle Toolbar'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + 4', isMac), description: 'Toggle Settings'),
                    if (isMac) _CheatsheetItem(theme: theme, keys: 'Cmd + ,', description: 'Settings'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + 5', isMac), description: 'Typewriter Scrolling'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + 6', isMac), description: 'Paragraph Focus'),
                    _CheatsheetItem(
                      theme: theme,
                      keys: isMacOSOnly
                          ? 'Cmd + Ctrl + F'
                          : (isMac ? 'Cmd + Opt + Enter' : 'Alt + Enter'),
                      description: 'Toggle Fullscreen',
                    ),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + A', isMac), description: 'Attributions'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + Shift + A', isMac), description: 'Set Alarm'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + C', isMac), description: 'Peek Clock / Dismiss Alarm'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + S', isMac), description: 'Peek Session'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + P', isMac), description: 'Toggle Pomodoro'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + Shift + P', isMac), description: 'Reset Pomodoro'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + Shift + S', isMac), description: 'Toggle Sprint'),
                    _CheatsheetItem(theme: theme, keys: _getKeys('Alt + N', isMac), description: 'Add Note'),
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

  String _getKeys(String winKeys, bool isMac) {
    if (!isMac) return winKeys;
    return winKeys
        .replaceAll('Alt + Shift +', 'Cmd + Opt + Shift +')
        .replaceAll('Alt +', 'Cmd + Opt +');
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
