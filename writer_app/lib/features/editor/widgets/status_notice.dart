// Description: A faint, self-dismissing status line ("Spell check off") shown
// top-centre after a keyboard toggle that has no visible control on screen.
//
// Ghost-UI rules: it uses the page's own colours (never a contrasting
// fill), is lifted off the page only by a soft drop shadow, ignores the
// pointer, and fades away on its own over two seconds.

import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';

OverlayEntry? _current;

/// Shows [message] over everything in [overlay]; a newer notice replaces an
/// older one that is still fading.
void showStatusNotice(OverlayState overlay, WriterTheme theme, String message) {
  _current?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _StatusNotice(
      key: UniqueKey(),
      theme: theme,
      message: message,
      onDone: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

class _StatusNotice extends StatefulWidget {
  final WriterTheme theme;
  final String message;
  final VoidCallback onDone;

  const _StatusNotice({
    super.key,
    required this.theme,
    required this.message,
    required this.onDone,
  });

  @override
  State<_StatusNotice> createState() => _StatusNoticeState();
}

class _StatusNoticeState extends State<_StatusNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..forward().whenComplete(() {
          if (mounted) widget.onDone();
        });

  // Holds near full strength for the first part, then eases out: a slow fade
  // rather than a blink.
  late final Animation<double> _opacity = Tween<double>(
    begin: 1,
    end: 0,
  ).chain(CurveTween(curve: Curves.easeInCubic)).animate(_fade);

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Positioned(
      top: 56,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: FadeTransition(
              opacity: _opacity,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  style: TextStyle(
                    color: theme.foregroundColor.withValues(alpha: 0.6),
                    fontSize: 12,
                    letterSpacing: 0.4,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
