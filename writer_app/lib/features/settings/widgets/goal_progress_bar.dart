// @trace FEAT-20260705-000000-0006
// Description: Thin, theme-driven ghost progress line for writing goals.

import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';

class GoalProgressBar extends StatelessWidget {
  /// Raw progress ratio; values above 1.0 are clamped for the fill width.
  final double progress;
  final WriterTheme theme;
  final double height;

  const GoalProgressBar({
    super.key,
    required this.progress,
    required this.theme,
    this.height = 2,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Container(
                height: height,
                width: double.infinity,
                color: theme.foregroundColor.withValues(alpha: 0.06),
              ),
              Container(
                height: height,
                width: constraints.maxWidth * clamped,
                color: theme.foregroundColor.withValues(alpha: 0.25),
              ),
            ],
          );
        },
      ),
    );
  }
}
