import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class PomodoroWidget extends StatefulWidget {
  final WriterTheme theme;
  final Duration remaining;
  final bool isActive;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;

  const PomodoroWidget({
    super.key,
    required this.theme,
    required this.remaining,
    required this.isActive,
    required this.onStart,
    required this.onPause,
    required this.onReset,
  });

  @override
  State<PomodoroWidget> createState() => _PomodoroWidgetState();
}

class _PomodoroWidgetState extends State<PomodoroWidget> {
  bool _isHovered = false;

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        opacity: _isHovered ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 200),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _format(widget.remaining),
              style: TextStyle(
                color: widget.theme.foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_isHovered) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(widget.isActive ? Icons.pause : Icons.play_arrow, size: 14),
                onPressed: widget.isActive ? widget.onPause : widget.onStart,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                color: widget.theme.foregroundColor,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 14),
                onPressed: widget.onReset,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(left: 2),
                color: widget.theme.foregroundColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
