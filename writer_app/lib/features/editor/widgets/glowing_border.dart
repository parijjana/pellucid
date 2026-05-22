// @trace FEAT-20260517-115000-0004
// Description: A widget that renders an animated "River of Stars" border.
// Specification: Refer to ANIMATION_SPEC.md

import 'dart:ui';
import 'dart:math' as math;
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
      duration: const Duration(seconds: 10), // Slow and deliberate
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
        return Stack(
          children: [
            // The content child is at the bottom
            widget.child,
            
            // The River Overlay is on top
            if (widget.isActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RiverPainter(
                      progress: _controller.value,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
          ],
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
    // Outer border path
    final Rect rect = Offset.zero & size;
    // Note: No radius here as it's the app edge, but using a small one for safety
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    
    final Path path = Path()..addRRect(rrect);
    final PathMetric metric = path.computeMetrics().first;
    final double totalLength = metric.length;
    
    // 1. Base faint border
    final Paint basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withValues(alpha: 0.05);
    canvas.drawRRect(rrect, basePaint);

    // 2. High-Fidelity Glow Segment
    final double segmentLength = totalLength * 0.15; // 15% of perimeter
    final double startPos = (progress * totalLength) % totalLength;
    
    final Path highlightPath = Path();
    if (startPos + segmentLength <= totalLength) {
      highlightPath.addPath(metric.extractPath(startPos, startPos + segmentLength), Offset.zero);
    } else {
      highlightPath.addPath(metric.extractPath(startPos, totalLength), Offset.zero);
      highlightPath.addPath(metric.extractPath(0, segmentLength - (totalLength - startPos)), Offset.zero);
    }

    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.25
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
      ..color = color.withValues(alpha: 0.6);

    canvas.drawPath(highlightPath, glowPaint);

    // 3. The "River of Stars" (Tiny white dots at the wavefront)
    final Paint starPaint = Paint()..color = Colors.white;
    final math.Random random = math.Random(42); // Deterministic seed for stable-ish distribution
    
    // Wavefront is the end of the extracted path
    final double wavefrontPos = (startPos + segmentLength) % totalLength;
    
    for (int i = 0; i < 12; i++) {
      // Scatter stars slightly behind the wavefront
      final double starOffset = wavefrontPos - (random.nextDouble() * segmentLength * 0.4);
      final Tangent? tangent = metric.getTangentForOffset((starOffset + totalLength) % totalLength);
      
      if (tangent != null) {
        final double jitterX = (random.nextDouble() - 0.5) * 6.0;
        final double jitterY = (random.nextDouble() - 0.5) * 6.0;
        final double starRadius = 0.4 + (random.nextDouble() * 0.8);
        final double opacity = 0.3 + (random.nextDouble() * 0.7);
        
        starPaint.color = Colors.white.withValues(alpha: opacity);
        canvas.drawCircle(tangent.position + Offset(jitterX, jitterY), starRadius, starPaint);
      }
    }

    // 4. Inner core highlight
    final Paint corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.8);
    
    canvas.drawPath(highlightPath, corePaint);
  }

  @override
  bool shouldRepaint(covariant _RiverPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
