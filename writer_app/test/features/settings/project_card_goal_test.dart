// @trace FEAT-20260705-000000-0006
// Description: Widget tests verifying the project-card goal indicator only
// appears when a goal is set.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/widgets/project_card.dart';
import 'package:pellucid/features/settings/widgets/project_goal_line.dart';

void main() {
  final theme = WriterTheme.presets.first;

  Widget wrap(ProjectCard card) => MaterialApp(home: Scaffold(body: card));

  testWidgets('no goal line rendered when wordGoal is unset', (tester) async {
    await tester.pumpWidget(wrap(ProjectCard(
      name: 'Test',
      wordCount: 100,
      timeSpent: const Duration(minutes: 5),
      isActive: false,
      theme: theme,
      onTap: () {},
      onLaunch: () {},
      onOpenFolder: () {},
    )));

    expect(find.byType(ProjectGoalLine), findsNothing);
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
  });

  testWidgets('goal line and percent rendered when wordGoal is set', (tester) async {
    await tester.pumpWidget(wrap(ProjectCard(
      name: 'Test',
      wordCount: 500,
      timeSpent: const Duration(minutes: 5),
      isActive: true,
      theme: theme,
      wordGoal: 1000,
      onTap: () {},
      onLaunch: () {},
      onOpenFolder: () {},
    )));

    expect(find.byType(ProjectGoalLine), findsOneWidget);
    expect(find.text('50% of 1000'), findsOneWidget);
  });

  testWidgets('set-goal button appears only when onSetGoal provided', (tester) async {
    await tester.pumpWidget(wrap(ProjectCard(
      name: 'Test',
      wordCount: 0,
      timeSpent: Duration.zero,
      isActive: true,
      theme: theme,
      onSetGoal: () {},
      onTap: () {},
      onLaunch: () {},
      onOpenFolder: () {},
    )));

    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
  });
}
