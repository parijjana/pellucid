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
}
