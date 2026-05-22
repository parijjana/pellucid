// @trace FEAT-20260516-115000-0003
// Description: Minimal formatting toolbar for the editor (Flat Style).

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class FormattingToolbar extends StatelessWidget {
  final WriterTheme theme;
  final Function(String) onApplyFormat;

  const FormattingToolbar({
    super.key,
    required this.theme,
    required this.onApplyFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _labelButton('TITLE', () => onApplyFormat('# ')),
          _labelButton('HEADING', () => onApplyFormat('## ')),
          _labelButton('BODY', () => onApplyFormat('body')),
          _labelButton('BULLET', () => onApplyFormat('- ')),
          const SizedBox(width: 12),
          Container(
            height: 12, width: 1, 
            color: theme.foregroundColor.withValues(alpha: 0.05)
          ),
          const SizedBox(width: 12),
          _labelButton('BOLD', () => onApplyFormat('**')),
          _labelButton('ITALIC', () => onApplyFormat('*')),
        ],
      ),
    );
  }

  Widget _labelButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.foregroundColor.withValues(alpha: 0.4),
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
