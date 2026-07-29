// @trace FEAT-20260705-000000-0006
// Description: Ghost status-bar surface for the writing sprint timer/result.

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../screenshot_mode.dart';

class SprintWidget extends StatefulWidget {
  final WriterTheme theme;
  final bool isActive;
  final Duration remaining;
  final int? lastWords;
  final VoidCallback onDismiss;

  const SprintWidget({
    super.key,
    required this.theme,
    required this.isActive,
    required this.remaining,
    required this.lastWords,
    required this.onDismiss,
  });

  @override
  State<SprintWidget> createState() => _SprintWidgetState();
}

class _SprintWidgetState extends State<SprintWidget> {
  bool _isHovered = false;

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.theme.foregroundColor;
    final bool showResult = !widget.isActive && widget.lastWords != null;
    final String label = widget.isActive
        ? _format(widget.remaining)
        : '${widget.lastWords! >= 0 ? '+' : ''}${widget.lastWords} words';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: showResult ? widget.onDismiss : null,
        child: AnimatedOpacity(
          opacity: (_isHovered || kScreenshotCaptureMode) ? 1.0 : 0.3,
          duration: const Duration(milliseconds: 200),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isActive ? Icons.bolt : Icons.check,
                size: 12,
                color: fg,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
