import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../caret_formatting.dart';
import '../providers/theme_provider.dart';
import 'formatting_toolbar.dart' show formatActiveTint;

class MobilePersistentToolbar extends StatelessWidget {
  final WriterTheme theme;
  final Function(String) onApplyFormat;
  final VoidCallback onSettingsTap;

  /// Formatting at the caret, shown as active buttons (item 25).
  final ValueListenable<FormattingState>? formatting;

  const MobilePersistentToolbar({
    super.key,
    required this.theme,
    required this.onApplyFormat,
    required this.onSettingsTap,
    this.formatting,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FormattingState>(
      valueListenable: formatting ?? caretFormatting,
      builder: (context, f, _) => _build(f),
    );
  }

  Widget _build(FormattingState f) {
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
                    active: f.block == BlockStyle.title,
                    onPressed: () => onApplyFormat('# '),
                  ),
                  _ToolbarTextButton(
                    label: 'HEADING',
                    theme: theme,
                    active: f.block == BlockStyle.heading,
                    onPressed: () => onApplyFormat('## '),
                  ),
                  _ToolbarTextButton(
                    label: 'SUBHEAD',
                    theme: theme,
                    active: f.block == BlockStyle.subheading,
                    onPressed: () => onApplyFormat('### '),
                  ),
                  _ToolbarTextButton(
                    label: 'BODY',
                    theme: theme,
                    active: f.block == BlockStyle.body && f.list == ListStyle.none,
                    onPressed: () => onApplyFormat('body'),
                  ),
                  _ToolbarTextButton(
                    label: 'BULLET',
                    theme: theme,
                    active: f.list == ListStyle.bullet,
                    onPressed: () => onApplyFormat('- '),
                  ),
                  _ToolbarTextButton(
                    label: 'NUMBER',
                    theme: theme,
                    active: f.list == ListStyle.numbered,
                    onPressed: () => onApplyFormat('1. '),
                  ),
                  _ToolbarTextButton(
                    label: 'CHECKLIST',
                    theme: theme,
                    active: f.list == ListStyle.checklist,
                    onPressed: () => onApplyFormat('- [ ] '),
                  ),
                  _ToolbarTextButton(
                    label: 'OUTDENT',
                    theme: theme,
                    active: false,
                    onPressed: () => onApplyFormat('outdent'),
                  ),
                  _ToolbarTextButton(
                    label: 'INDENT',
                    theme: theme,
                    active: false,
                    onPressed: () => onApplyFormat('indent'),
                  ),
                  _ToolbarTextButton(
                    label: 'QUOTE',
                    theme: theme,
                    active: f.block == BlockStyle.quote,
                    onPressed: () => onApplyFormat('> '),
                  ),
                  _ToolbarTextButton(
                    label: 'BOLD',
                    theme: theme,
                    active: f.bold,
                    onPressed: () => onApplyFormat('**'),
                  ),
                  _ToolbarTextButton(
                    label: 'ITALIC',
                    theme: theme,
                    active: f.italic,
                    onPressed: () => onApplyFormat('*'),
                  ),
                  _ToolbarTextButton(
                    label: 'STRIKE',
                    theme: theme,
                    active: f.strikethrough,
                    onPressed: () => onApplyFormat('~~'),
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
  final bool active;

  const _ToolbarTextButton({
    required this.label,
    required this.theme,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: ValueKey('format-$label'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.foregroundColor.withValues(alpha: active ? 1.0 : 0.6),
        backgroundColor: active ? formatActiveTint(theme) : null,
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
