// PEL-11 / MAC-5: every ProjectCard variant must fit the grid cell it is given
// by the Settings screen (maxCrossAxisExtent 220, mainAxisExtent kProjectCardExtent).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/widgets/project_card.dart';

void main() {
  for (final active in [false, true]) {
    for (final goal in [null, 5000]) {
      testWidgets('card fits its grid cell (active=$active goal=$goal)', (tester) async {
        final theme = WriterTheme.presets.first;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: kProjectCardExtent,
                ),
                itemCount: 1,
                itemBuilder: (_, _) => ProjectCard(
                  name: 'A rather long project name here',
                  wordCount: 123456,
                  timeSpent: const Duration(hours: 12, minutes: 5),
                  isActive: active,
                  theme: theme,
                  wordGoal: goal,
                  onSetGoal: () {},
                  onRename: () {},
                  onTap: () {},
                  onLaunch: () {},
                  onOpenFolder: () {},
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
