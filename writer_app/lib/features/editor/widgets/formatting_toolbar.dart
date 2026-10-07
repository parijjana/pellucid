// @trace FEAT-20260516-115000-0003
// Description: Minimal formatting toolbar for the editor (Flat Style).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../caret_formatting.dart';
import '../providers/theme_provider.dart';

class FormattingToolbar extends StatelessWidget {
  final WriterTheme theme;
  final Function(String) onApplyFormat;

  /// Formatting at the caret, shown as active buttons (item 25).
  final ValueListenable<FormattingState>? formatting;

  const FormattingToolbar({
    super.key,
    required this.theme,
    required this.onApplyFormat,
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
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
      ),
      // Scales down on narrow windows instead of overflowing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _labelButton('TITLE', () => onApplyFormat('# '), f.block == BlockStyle.title),
          _labelButton('HEADING', () => onApplyFormat('## '), f.block == BlockStyle.heading),
          _labelButton('SUBHEAD', () => onApplyFormat('### '), f.block == BlockStyle.subheading),
          _labelButton('BODY', () => onApplyFormat('body'), f.block == BlockStyle.body && f.list == ListStyle.none),
          _labelButton('BULLET', () => onApplyFormat('- '), f.list == ListStyle.bullet),
          _labelButton('QUOTE', () => onApplyFormat('> '), false),
          const SizedBox(width: 12),
          Container(
            height: 12, width: 1, 
            color: theme.foregroundColor.withValues(alpha: 0.05)
          ),
          const SizedBox(width: 12),
          _labelButton('BOLD', () => onApplyFormat('**'), f.bold),
          _labelButton('ITALIC', () => onApplyFormat('*'), f.italic),
          _labelButton('STRIKE', () => onApplyFormat('~~'), f.strikethrough),
        ],
        ),
      ),
    );
  }

  Widget _labelButton(String label, VoidCallback onPressed, bool active) {
    return TextButton(
      key: ValueKey('format-$label'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.foregroundColor,
        backgroundColor: active ? formatActiveTint(theme) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10),
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

/// Background of an active formatting button: a faint wash of the text colour,
/// so it reads on every theme.
Color formatActiveTint(WriterTheme theme) => theme.foregroundColor.withValues(alpha: 0.10);
