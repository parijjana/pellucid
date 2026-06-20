import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class MobilePersistentToolbar extends StatelessWidget {
  final WriterTheme theme;
  final Function(String) onApplyFormat;
  final VoidCallback onSettingsTap;

  const MobilePersistentToolbar({
    super.key,
    required this.theme,
    required this.onApplyFormat,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _ToolbarTextButton(
                    label: 'TITLE',
                    theme: theme,
                    onPressed: () => onApplyFormat('# '),
                  ),
                  _ToolbarTextButton(
                    label: 'HEADING',
                    theme: theme,
                    onPressed: () => onApplyFormat('## '),
                  ),
                  _ToolbarTextButton(
                    label: 'BODY',
                    theme: theme,
                    onPressed: () => onApplyFormat('body'),
                  ),
                  _ToolbarTextButton(
                    label: 'BULLET',
                    theme: theme,
                    onPressed: () => onApplyFormat('- '),
                  ),
                  _ToolbarTextButton(
                    label: 'BOLD',
                    theme: theme,
                    onPressed: () => onApplyFormat('**'),
                  ),
                  _ToolbarTextButton(
                    label: 'ITALIC',
                    theme: theme,
                    onPressed: () => onApplyFormat('*'),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            color: theme.foregroundColor.withValues(alpha: 0.1),
          ),
          IconButton(
            icon: Icon(Icons.settings, size: 20, color: theme.foregroundColor.withValues(alpha: 0.5)),
            onPressed: onSettingsTap,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _ToolbarTextButton extends StatelessWidget {
  final String label;
  final WriterTheme theme;
  final VoidCallback onPressed;

  const _ToolbarTextButton({
    required this.label,
    required this.theme,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.foregroundColor.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      child: Text(label),
    );
  }
}
