// @trace FEAT-20260705-000000-0006
// Description: Ghost per-project word-goal progress line with a faint percent.

import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';
import '../providers/goal_progress.dart';
import 'goal_progress_bar.dart';

class ProjectGoalLine extends StatelessWidget {
  final int wordCount;
  final int wordGoal;
  final WriterTheme theme;

  const ProjectGoalLine({
    super.key,
    required this.wordCount,
    required this.wordGoal,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goalProgress(wordCount, wordGoal);
    final percent = (progress * 100).clamp(0, 999).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GoalProgressBar(progress: progress, theme: theme),
        const SizedBox(height: 3),
        Text(
          '$percent% of $wordGoal',
          style: TextStyle(
            color: theme.foregroundColor.withValues(alpha: 0.3),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
