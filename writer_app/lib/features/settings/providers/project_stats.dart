// @trace FEAT-20260517-120000-0005
// Description: Model for project-specific statistics (word count and time spent).

import 'goal_progress.dart';

class ProjectStats {
  final int totalWordCount;
  final Duration totalTimeSpent;

  /// Optional total-word target for the project. Null (or unset) means no goal.
  final int? wordGoal;

  ProjectStats({
    this.totalWordCount = 0,
    this.totalTimeSpent = Duration.zero,
    this.wordGoal,
  });

  /// Whether a usable word goal is configured.
  bool get hasWordGoal => wordGoal != null && wordGoal! > 0;

  /// Raw progress ratio towards the word goal (0.0 when unset).
  double get wordGoalProgress => goalProgress(totalWordCount, wordGoal);

  /// Whether the project word goal has been reached.
  bool get isWordGoalMet => goalMet(totalWordCount, wordGoal);

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'totalWordCount': totalWordCount,
      'totalTimeSeconds': totalTimeSpent.inSeconds,
    };
    // Only emit when set, keeping output backward-compatible byte-for-byte.
    if (wordGoal != null) map['wordGoal'] = wordGoal;
    return map;
  }

  factory ProjectStats.fromJson(Map<String, dynamic> json) {
    return ProjectStats(
      totalWordCount: json['totalWordCount'] ?? 0,
      totalTimeSpent: Duration(seconds: json['totalTimeSeconds'] ?? 0),
      wordGoal: json['wordGoal'],
    );
  }

  ProjectStats copyWith({
    int? totalWordCount,
    Duration? totalTimeSpent,
    int? wordGoal,
  }) {
    return ProjectStats(
      totalWordCount: totalWordCount ?? this.totalWordCount,
      totalTimeSpent: totalTimeSpent ?? this.totalTimeSpent,
      wordGoal: wordGoal ?? this.wordGoal,
    );
  }
}
