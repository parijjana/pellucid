// @trace FEAT-20260517-120000-0005
// Description: Model for project-specific statistics (word count and time spent).

class ProjectStats {
  final int totalWordCount;
  final Duration totalTimeSpent;

  ProjectStats({
    this.totalWordCount = 0,
    this.totalTimeSpent = Duration.zero,
  });

  Map<String, dynamic> toJson() {
    return {
      'totalWordCount': totalWordCount,
      'totalTimeSeconds': totalTimeSpent.inSeconds,
    };
  }

  factory ProjectStats.fromJson(Map<String, dynamic> json) {
    return ProjectStats(
      totalWordCount: json['totalWordCount'] ?? 0,
      totalTimeSpent: Duration(seconds: json['totalTimeSeconds'] ?? 0),
    );
  }

  ProjectStats copyWith({
    int? totalWordCount,
    Duration? totalTimeSpent,
  }) {
    return ProjectStats(
      totalWordCount: totalWordCount ?? this.totalWordCount,
      totalTimeSpent: totalTimeSpent ?? this.totalTimeSpent,
    );
  }
}
