// @trace FEAT-20260517-115000-0004
// Description: Card widgets for project selection and creation.

import 'package:flutter/material.dart';
import '../providers/settings_provider.dart';
import '../../editor/providers/theme_provider.dart';

class ProjectCard extends StatelessWidget {
  final String name;
  final int wordCount;
  final Duration timeSpent;
  final bool isActive;
  final WriterTheme theme;
  final VoidCallback onTap;

  const ProjectCard({
    super.key,
    required this.name,
    required this.wordCount,
    required this.timeSpent,
    required this.isActive,
    required this.theme,
    required this.onTap,
  });

  String _formatTime(Duration d) {
    final hours = d.inSeconds / 3600;
    return '${hours.toStringAsFixed(1)} hrs';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.sidebarColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.blue : theme.foregroundColor.withValues(alpha: 0.1),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: theme.foregroundColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive)
                  const Icon(Icons.check_circle, color: Colors.blue, size: 16),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statText('$wordCount words', theme),
                    const SizedBox(height: 4),
                    _statText(_formatTime(timeSpent), theme),
                  ],
                ),
                if (isActive)
                  _HistoryButton(theme: theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statText(String text, WriterTheme theme) {
    return Text(
      text,
      style: TextStyle(
        color: theme.foregroundColor.withValues(alpha: 0.5),
        fontSize: 11,
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  final WriterTheme theme;
  const _HistoryButton({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.foregroundColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.history,
        size: 14,
        color: theme.foregroundColor.withValues(alpha: 0.4),
      ),
    );
  }
}

class NewProjectCard extends StatelessWidget {
  final WriterTheme theme;
  final VoidCallback onTap;

  const NewProjectCard({
    super.key,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: DottedBorderPainter(
          color: theme.foregroundColor.withValues(alpha: 0.2),
          strokeWidth: 2,
          gap: 4,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: theme.foregroundColor.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text(
                'NEW PROJECT',
                style: TextStyle(
                  color: theme.foregroundColor.withValues(alpha: 0.3),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DottedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  DottedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(8)));

    final dashPath = Path();
    double distance = 0.0;
    for (final pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        dashPath.addPath(
          pathMetric.extractPath(distance, distance + gap),
          Offset.zero,
        );
        distance += gap * 2;
      }
      distance = 0.0;
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
