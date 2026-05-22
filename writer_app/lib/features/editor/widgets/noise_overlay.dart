// @trace FEAT-20260517-115000-0004
// Description: A widget that applies a subtle noise texture to its child for a tactile feel.

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class NoiseOverlay extends StatelessWidget {
  final Widget child;
  final double opacity;

  const NoiseOverlay({
    super.key,
    required this.child,
    this.opacity = 0.05,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0.001) return child;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: const _NoiseTexture(),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoiseTexture extends StatelessWidget {
  const _NoiseTexture();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _NoisePainter(),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final random = Random(42);
    
    // Draw fine grain noise using points
    final List<Offset> points = [];
    for (int i = 0; i < 10000; i++) {
      points.add(Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      ));
    }
    
    canvas.drawPoints(
      ui.PointMode.points,
      points,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
