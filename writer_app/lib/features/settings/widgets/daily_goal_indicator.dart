// @trace FEAT-20260705-000000-0006
// Description: Faint daily-word-goal progress indicator with a quiet
// acknowledgement glyph when the day's goal is met. Renders nothing if unset.

import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';
import '../providers/goal_progress.dart';
import 'goal_progress_bar.dart';

class DailyGoalIndicator extends StatelessWidget {
  final int wordsToday;
  final int goal;
  final WriterTheme theme;

  const DailyGoalIndicator({
    super.key,
    required this.wordsToday,
    required this.goal,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (goal <= 0) return const SizedBox.shrink();

    final progress = goalProgress(wordsToday, goal);
    final met = goalMet(wordsToday, goal);
    final fg = theme.foregroundColor;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Daily Goal',
                      style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 13)),
                  if (met) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check, size: 13, color: fg.withValues(alpha: 0.35)),
                  ],
                ],
              ),
              Text('$wordsToday / $goal',
                  style: TextStyle(color: fg.withValues(alpha: 0.35), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          GoalProgressBar(progress: progress, theme: theme),
        ],
      ),
    );
  }
}
