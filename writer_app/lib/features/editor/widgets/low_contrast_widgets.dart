import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class LowContrastIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final WriterTheme theme;
  final double size;
  final bool flipX;

  const LowContrastIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.theme,
    this.size = 18,
    this.flipX = false,
  });

  @override
  State<LowContrastIconButton> createState() => _LowContrastIconButtonState();
}

class _LowContrastIconButtonState extends State<LowContrastIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isHovered ? 1.0 : 0.2,
        child: IconButton(
          icon: widget.flipX 
            ? Transform.flip(flipX: true, child: Icon(widget.icon, size: widget.size))
            : Icon(widget.icon, size: widget.size),
          onPressed: widget.onPressed,
          color: widget.theme.foregroundColor,
        ),
      ),
    );
  }
}

class LowContrastText extends StatefulWidget {
  final String label;
  final WriterTheme theme;
  final double fontSize;

  const LowContrastText({
    super.key,
    required this.label,
    required this.theme,
    this.fontSize = 11,
  });

  @override
  State<LowContrastText> createState() => _LowContrastTextState();
}

class _LowContrastTextState extends State<LowContrastText> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isHovered ? 1.0 : 0.25,
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.theme.foregroundColor,
            fontSize: widget.fontSize,
          ),
        ),
      ),
    );
  }
}
