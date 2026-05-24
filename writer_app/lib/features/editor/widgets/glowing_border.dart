// @trace FEAT-20260517-115000-0004
// Description: A widget that renders an animated "River of Stars" border.
// Specification: Refer to ANIMATION_SPEC.md

import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

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
    final theme = context.watch<ThemeProvider>().currentTheme;
    const double borderThickness = 20.0; // Widened border as requested

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Container(
          color: theme.backgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(borderThickness),
            child: Stack(
              clipBehavior: Clip.none, // Allows positioned child to render outside the padded Stack bounds
              children: [
                // The actual usable app content (Navigator)
                child ?? const SizedBox.shrink(),
                
                // Glowing River Overlay flowing through the reserved space
                if (widget.isActive)
                  Positioned.fill(
                    left: -borderThickness,
                    top: -borderThickness,
                    right: -borderThickness,
                    bottom: -borderThickness,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _RiverPainter(
                          progress: _controller.value,
                          color: widget.color,
                          borderThickness: borderThickness,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RiverPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double borderThickness;

  _RiverPainter({
    required this.progress,
    required this.color,
    required this.borderThickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    
    // Deflate by a tiny offset (4.0) to run the path right up to the edge of the window!
    final Rect rect = (Offset.zero & size).deflate(4.0);
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    
    final Path path = Path()..addRRect(rrect);
    final List<ui.PathMetric> metricsList = path.computeMetrics().toList();
    if (metricsList.isEmpty) return;
    final ui.PathMetric metric = metricsList.first;
    final double totalLength = metric.length;
    
    // Draw Base Faint Border
    final Paint basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: 0.05);
    canvas.drawRRect(rrect, basePaint);

    // High-Fidelity Glow Segment
    final double segmentLength = totalLength * 0.15; // 15% of perimeter
    final double startPos = (progress * totalLength) % totalLength;
    
    final Path highlightPath = Path();
    if (startPos + segmentLength <= totalLength) {
      highlightPath.addPath(metric.extractPath(startPos, startPos + segmentLength), Offset.zero);
    } else {
      highlightPath.addPath(metric.extractPath(startPos, totalLength), Offset.zero);
      highlightPath.addPath(metric.extractPath(0, segmentLength - (totalLength - startPos)), Offset.zero);
    }

    final double wavefrontPos = (startPos + segmentLength) % totalLength;
    final ui.Tangent? tailTangent = metric.getTangentForOffset(startPos);
    final ui.Tangent? wavefrontTangent = metric.getTangentForOffset(wavefrontPos);

    // Multi-stroke glow simulation for 100% GPU safety and compatibility (no MaskFilter.blur + shader clash)
    for (double w = 4.0; w <= 28.0; w += 4.0) {
      final double opacityFactor = 0.25 * (1.0 - (w / 28.0));
      final Paint glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round;

      if (tailTangent != null && wavefrontTangent != null) {
        final Offset from = tailTangent.position;
        final Offset to = wavefrontTangent.position;
        glowPaint.shader = ui.Gradient.linear(
          from,
          to,
          [
            color.withValues(alpha: 0.0), // transparent at tail
            color.withValues(alpha: opacityFactor), // fading/solid color at wavefront
          ],
        );
      } else {
        glowPaint.color = color.withValues(alpha: opacityFactor * 0.8);
      }

      canvas.drawPath(highlightPath, glowPaint);
    }

    // Sharp Inner Core Highlight (thickened from 1.5px to 3.0px)
    final Paint corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    if (tailTangent != null && wavefrontTangent != null) {
      final Offset from = tailTangent.position;
      final Offset to = wavefrontTangent.position;
      corePaint.shader = ui.Gradient.linear(
        from,
        to,
        [
          color.withValues(alpha: 0.0), // transparent at tail
          color.withValues(alpha: 1.0), // solid color at wavefront
        ],
      );
    } else {
      corePaint.color = color.withValues(alpha: 0.8);
    }

    canvas.drawPath(highlightPath, corePaint);

    // The "River of Stars" (Tiny white dots at the wavefront, scaled sizes and jitter to match wider stream)
    final Paint starPaint = Paint()..color = Colors.white;
    final math.Random random = math.Random(42); // Deterministic seed for stable-ish distribution
    
    for (int i = 0; i < 12; i++) {
      // Scatter stars slightly behind the wavefront
      final double starOffset = wavefrontPos - (random.nextDouble() * segmentLength * 0.4);
      final ui.Tangent? tangent = metric.getTangentForOffset((starOffset + totalLength) % totalLength);
      
      if (tangent != null) {
        final double jitterX = (random.nextDouble() - 0.5) * 12.0;
        final double jitterY = (random.nextDouble() - 0.5) * 12.0;
        final double starRadius = 0.8 + (random.nextDouble() * 1.6);
        final double opacity = 0.3 + (random.nextDouble() * 0.7);
        
        starPaint.color = Colors.white.withValues(alpha: opacity);
        canvas.drawCircle(tangent.position + Offset(jitterX, jitterY), starRadius, starPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RiverPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.borderThickness != borderThickness;
}
