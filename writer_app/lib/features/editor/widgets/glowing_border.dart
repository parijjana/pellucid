// @trace FEAT-20260517-115000-0004
// Description: A widget that renders an animated glowing "river" border.

import 'package:flutter/material.dart';

class GlowingBorder extends StatefulWidget {
  final Widget child;
  final bool isActive;
  final Color color;

  const GlowingBorder({
    super.key,
    required this.child,
    required this.isActive,
    required this.color,
  });

  @override
  State<GlowingBorder> createState() => _GlowingBorderState();
}

class _GlowingBorderState extends State<GlowingBorder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isActive) _controller.repeat();
  }

  @override
  void didUpdateWidget(GlowingBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: widget.isActive
              ? BoxDecoration(
                  border: Border.all(color: Colors.transparent, width: 2),
                )
              : null,
          child: Stack(
            children: [
              if (widget.isActive)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RiverPainter(
                      progress: _controller.value,
                      color: widget.color,
                    ),
                  ),
                ),
              widget.child,
            ],
          ),
        );
      },
    );
  }
}

class _RiverPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RiverPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.8),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(progress * 2 * 3.141592653589793),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _RiverPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
