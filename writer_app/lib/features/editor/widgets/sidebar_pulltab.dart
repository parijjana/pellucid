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
    final double topOffset = MediaQuery.of(context).size.height / 2 - 30;
    final isLeft = direction == AxisDirection.left;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: isLeft ? (isOpen ? 250 : 0) : null,
      right: !isLeft ? (isOpen ? 300 : 0) : null,
      top: topOffset,
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
