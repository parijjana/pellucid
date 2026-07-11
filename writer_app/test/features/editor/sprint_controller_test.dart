// @trace FEAT-20260705-000000-0006
// Description: Unit tests for SprintController baseline/delta math. Uses stop()
// which shares the same completion path (_finish) as timer expiry, so the
// baseline->end word delta is exercised without pumping real timers.

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';

void main() {
  group('SprintController', () {
    test('reports positive words written between start and end', () {
      final controller = SprintController();
      int words = 100;
      controller.start(currentWords: () => words, duration: const Duration(seconds: 2));

      expect(controller.isActive, isTrue);
      expect(controller.remaining, const Duration(seconds: 2));

      words = 130; // wrote 30 words during the sprint
      controller.stop();

      expect(controller.isActive, isFalse);
      expect(controller.lastSprintWords, 30);
    });

    test('reports negative delta when the word count drops', () {
      final controller = SprintController();
      int words = 50;
      controller.start(currentWords: () => words, duration: const Duration(seconds: 2));

      words = 44; // deleted 6 words
      controller.stop();

      expect(controller.lastSprintWords, -6);
    });

    test('reports zero when word count is unchanged', () {
      final controller = SprintController();
      controller.start(currentWords: () => 10, duration: const Duration(seconds: 2));
      controller.stop();

      expect(controller.lastSprintWords, 0);
    });

    test('start is ignored while a sprint is already active', () {
      final controller = SprintController();
      int words = 10;
      controller.start(currentWords: () => words, duration: const Duration(seconds: 2));
      // Second start must not re-baseline.
      words = 999;
      controller.start(currentWords: () => words, duration: const Duration(seconds: 2));

      words = 25; // net +15 from the original baseline of 10
      controller.stop();
      expect(controller.lastSprintWords, 15);
    });

    test('clearResult removes the last result', () {
      final controller = SprintController();
      controller.start(currentWords: () => 5, duration: const Duration(seconds: 1));
      controller.stop();

      expect(controller.lastSprintWords, isNotNull);
      controller.clearResult();
      expect(controller.lastSprintWords, isNull);
    });
  });
}
