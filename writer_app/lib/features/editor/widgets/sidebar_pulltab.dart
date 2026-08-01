import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class SidebarPulltab extends StatelessWidget {
  final WriterTheme theme;
  final AxisDirection direction;
  final bool isOpen;
  final VoidCallback onTap;

  const SidebarPulltab({
    super.key,
    required this.theme,
    required this.direction,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Thumb-height, not vertical-center: on a large iPad the screen center is
    // a stretch for a one-handed thumb, whether held in one hand or propped
    // up with the FAB dock's touch status bar occupying the very bottom.
    // Anchor from the bottom instead of the vertical center, clearing both
    // the home-indicator safe area and the touch status bar beneath it, so
    // the tab sits in the comfortable lower-third "thumb zone" on any touch
    // device (phone or tablet) rather than drifting to mid-screen on a 13"
    // iPad.
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double bottomOffset = bottomInset + 120;
    final isLeft = direction == AxisDirection.left;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: isLeft ? (isOpen ? 250 : 0) : null,
      right: !isLeft ? (isOpen ? 300 : 0) : null,
      bottom: bottomOffset,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 24,
          height: 60,
          decoration: BoxDecoration(
            color: theme.sidebarColor.withValues(alpha: 0.95),
            borderRadius: BorderRadius.horizontal(
              left: isLeft ? Radius.zero : const Radius.circular(8),
              right: isLeft ? const Radius.circular(8) : Radius.zero,
            ),
            border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.1)),
          ),
          child: Center(
            child: Icon(
              isLeft
                  ? (isOpen ? Icons.chevron_left : Icons.chevron_right)
                  : (isOpen ? Icons.chevron_right : Icons.chevron_left),
              size: 16,
              color: theme.foregroundColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
