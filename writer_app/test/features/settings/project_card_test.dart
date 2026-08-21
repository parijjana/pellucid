import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/widgets/project_card.dart';

void main() {
  testWidgets('ProjectCard triggering onTap and onLaunch on double tap', (WidgetTester tester) async {
    bool tapped = false;
    bool launched = false;

    final theme = WriterTheme.presets.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectCard(
            name: 'Test Project',
            wordCount: 100,
            timeSpent: const Duration(minutes: 5),
            isActive: false,
            theme: theme,
            onTap: () {
              tapped = true;
            },
            onLaunch: () {
              launched = true;
            },
            onOpenFolder: () {},
          ),
        ),
      ),
    );

    // Verify card is rendered
    expect(find.text('Test Project'), findsOneWidget);
    expect(tapped, false);
    expect(launched, false);

    // Perform single tap
    await tester.tap(find.text('Test Project'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tapped, true);
    expect(launched, false);

    // Reset tapped state
    tapped = false;

    // Perform double tap
    await tester.tap(find.text('Test Project'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Test Project'));
    await tester.pump(const Duration(milliseconds: 500)); // wait for double tap timeout

    expect(launched, true);
  });

  testWidgets('rename button is hidden when onRename is null', (WidgetTester tester) async {
    final theme = WriterTheme.presets.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectCard(
            name: 'User Manual',
            wordCount: 0,
            timeSpent: Duration.zero,
            isActive: false,
            theme: theme,
            onTap: () {},
            onLaunch: () {},
            onOpenFolder: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.drive_file_rename_outline), findsNothing);
    expect(find.byTooltip('Rename Project'), findsNothing);
  });

  testWidgets('rename button appears and invokes onRename when tapped', (WidgetTester tester) async {
    bool renameTapped = false;
    final theme = WriterTheme.presets.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectCard(
            name: 'Test Project',
            wordCount: 100,
            timeSpent: const Duration(minutes: 5),
            isActive: false,
            theme: theme,
            onTap: () {},
            onLaunch: () {},
            onOpenFolder: () {},
            onRename: () {
              renameTapped = true;
            },
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.drive_file_rename_outline), findsOneWidget);
    expect(find.byTooltip('Rename Project'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.drive_file_rename_outline));
    await tester.pump(const Duration(milliseconds: 350)); // wait past double-tap timeout

    expect(renameTapped, true);
  });

  testWidgets('stats stay on one line and all buttons render without overflow on a narrow card', (
    WidgetTester tester,
  ) async {
    final theme = WriterTheme.presets.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: ProjectCard(
              name: 'Narrow Project',
              wordCount: 101,
              timeSpent: const Duration(minutes: 6),
              isActive: true,
              theme: theme,
              wordGoal: 1000,
              onTap: () {},
              onLaunch: () {},
              onOpenFolder: () {},
              onSetGoal: () {},
              onRename: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // No overflow/render errors from squeezing the stats column.
    expect(tester.takeException(), isNull);

    // The word-count stat must render as a single line, not one
    // character per line (the original bug: an Expanded stats column
    // squeezed to near-zero width by the button row).
    final wordsFinder = find.text('101 words');
    expect(wordsFinder, findsOneWidget);
    final wordsSize = tester.getSize(wordsFinder);
    // A single-line "101 words" render is wide and short; a
    // one-character-per-line render would be narrow and tall.
    expect(wordsSize.width, greaterThan(wordsSize.height));

    // All six buttons (goal, launch, open-folder, rename, snapshots,
    // history) are present and rendered.
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
    expect(find.byIcon(Icons.drive_file_rename_outline), findsOneWidget);
    expect(find.byIcon(Icons.cloud_sync), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
  });
}
