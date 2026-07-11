// @trace FEAT-20260705-000000-0006
// Description: Unit tests for ProjectStats word-goal serialization and progress.

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/settings/providers/goal_progress.dart';

void main() {
  group('ProjectStats word goal serialization', () {
    test('round-trips a set word goal through JSON', () {
      final stats = ProjectStats(
        totalWordCount: 1200,
        totalTimeSpent: const Duration(seconds: 300),
        wordGoal: 5000,
      );
      final restored = ProjectStats.fromJson(stats.toJson());

      expect(restored.totalWordCount, 1200);
      expect(restored.totalTimeSpent.inSeconds, 300);
      expect(restored.wordGoal, 5000);
    });

    test('omits wordGoal from JSON when unset (backward-compatible output)', () {
      final stats = ProjectStats(totalWordCount: 10, totalTimeSpent: const Duration(seconds: 5));
      final json = stats.toJson();

      expect(json.containsKey('wordGoal'), isFalse);
      expect(json, {'totalWordCount': 10, 'totalTimeSeconds': 5});
    });

    test('deserializes legacy JSON without wordGoal as unset', () {
      final legacy = {'totalWordCount': 42, 'totalTimeSeconds': 60};
      final stats = ProjectStats.fromJson(legacy);

      expect(stats.wordGoal, isNull);
      expect(stats.hasWordGoal, isFalse);
      expect(stats.totalWordCount, 42);
    });

    test('copyWith preserves an existing goal across word-count updates', () {
      final stats = ProjectStats(totalWordCount: 100, wordGoal: 500);
      final updated = stats.copyWith(totalWordCount: 250);

      expect(updated.wordGoal, 500);
      expect(updated.totalWordCount, 250);
    });
  });

  group('goal progress calculations', () {
    test('unset goal yields 0 progress and is never met', () {
      expect(goalProgress(500, null), 0.0);
      expect(goalProgress(500, 0), 0.0);
      expect(goalMet(500, null), isFalse);
      expect(goalMet(500, 0), isFalse);
    });

    test('zero progress', () {
      expect(goalProgress(0, 1000), 0.0);
      expect(goalMet(0, 1000), isFalse);
    });

    test('partial progress', () {
      expect(goalProgress(250, 1000), 0.25);
      expect(goalMet(250, 1000), isFalse);
    });

    test('met exactly', () {
      expect(goalProgress(1000, 1000), 1.0);
      expect(goalMet(1000, 1000), isTrue);
    });

    test('exceeded goal', () {
      expect(goalProgress(1500, 1000), 1.5);
      expect(goalMet(1500, 1000), isTrue);
    });

    test('ProjectStats getters mirror the pure helpers', () {
      final stats = ProjectStats(totalWordCount: 1500, wordGoal: 1000);
      expect(stats.hasWordGoal, isTrue);
      expect(stats.wordGoalProgress, 1.5);
      expect(stats.isWordGoalMet, isTrue);
    });
  });
}
