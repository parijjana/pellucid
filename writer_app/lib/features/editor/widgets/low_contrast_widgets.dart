import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../screenshot_mode.dart';
import '../../../core/platform_context.dart';

// Ghost-UI resting opacity used once a real pointer (mouse/trackpad) has been
// observed anywhere in the app. This is the ORIGINAL dim-until-hover value —
// unchanged from before PointerTypeNotifier existed, so desktop/trackpad
// behavior is identical to before.
const double _pointerRestingOpacity = 0.2;
const double _pointerRestingOpacityText = 0.25;

// On a touch-only device, hover never fires, so a widget gated purely on
// `_isHovered` would sit at `_pointerRestingOpacity` forever — legible chrome
// permanently ghosted with no way to brighten it. Instead, once we know no
// pointer has ever been seen, we rest at a brighter-but-still-ghosted
// opacity: readable at a glance without a redesign of the Ghost UI aesthetic.
// Chosen empirically against the app's dark/light themes: 0.2 is too dim to
// read icon glyphs on touch (no hover ever brightens them), 1.0 would defeat
// the "ghost" premise entirely; ~0.55 sits roughly at the midpoint and reads
// clearly at iPad/iPhone viewing distance while still looking deliberately
// muted rather than "solid UI chrome".
const double _touchRestingOpacity = 0.55;

class LowContrastIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final WriterTheme theme;
  final double size;
  final bool flipX;
  final bool isSelected;

  const LowContrastIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.theme,
    this.size = 18,
    this.flipX = false,
    this.isSelected = false,
  });

  @override
  State<LowContrastIconButton> createState() => _LowContrastIconButtonState();
}

class _LowContrastIconButtonState extends State<LowContrastIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final double restingOpacity =
        isTouchWithoutPointer(context) ? _touchRestingOpacity : _pointerRestingOpacity;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: (_isHovered || widget.isSelected || kScreenshotCaptureMode) ? 1.0 : restingOpacity,
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
    final double restingOpacity =
        isTouchWithoutPointer(context) ? _touchRestingOpacity : _pointerRestingOpacityText;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: (_isHovered || kScreenshotCaptureMode) ? 1.0 : restingOpacity,
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
