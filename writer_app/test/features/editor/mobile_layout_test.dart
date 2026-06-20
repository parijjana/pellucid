import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/sidebar_pulltab.dart';
import 'package:pellucid/features/editor/widgets/mobile_persistent_toolbar.dart';
import 'package:pellucid/features/editor/widgets/cheatsheet_overlay.dart';

void main() {
  final testTheme = WriterTheme.presets[0]; // Dark default or similar

  group('SidebarPulltab Widget Tests', () {
    testWidgets('renders left pulltab chevron_right when closed', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SidebarPulltab(
                  theme: testTheme,
                  direction: AxisDirection.left,
                  isOpen: false,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.tap(find.byType(GestureDetector));
      expect(tapped, isTrue);
    });

    testWidgets('renders left pulltab chevron_left when open', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SidebarPulltab(
                  theme: testTheme,
                  direction: AxisDirection.left,
                  isOpen: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('renders right pulltab chevron_left when closed', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SidebarPulltab(
                  theme: testTheme,
                  direction: AxisDirection.right,
                  isOpen: false,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('renders right pulltab chevron_right when open', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SidebarPulltab(
                  theme: testTheme,
                  direction: AxisDirection.right,
                  isOpen: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });

  group('MobilePersistentToolbar Widget Tests', () {
    testWidgets('renders formatting buttons and triggers format and settings callbacks', (WidgetTester tester) async {
      String? appliedFormat;
      bool settingsTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobilePersistentToolbar(
              theme: testTheme,
              onApplyFormat: (format) => appliedFormat = format,
              onSettingsTap: () => settingsTapped = true,
            ),
          ),
        ),
      );

      // Verify formatting buttons are visible
      expect(find.text('TITLE'), findsOneWidget);
      expect(find.text('HEADING'), findsOneWidget);
      expect(find.text('BODY'), findsOneWidget);
      expect(find.text('BULLET'), findsOneWidget);
      expect(find.text('BOLD'), findsOneWidget);
      expect(find.text('ITALIC'), findsOneWidget);

      // Tap Title
      await tester.tap(find.text('TITLE'));
      expect(appliedFormat, '# ');

      // Tap Settings Icon
      expect(find.byIcon(Icons.settings), findsOneWidget);
      await tester.tap(find.byIcon(Icons.settings));
      expect(settingsTapped, isTrue);
    });
  });

  group('CheatsheetOverlayContent Widget Tests', () {
    testWidgets('renders shortcut list titles and headers', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheatsheetOverlayContent(theme: testTheme),
          ),
        ),
      );

      expect(find.text('KEYBOARD SHORTCUTS CHEATSHEET'), findsOneWidget);
      expect(find.text('Toggle ToC'), findsOneWidget);
      expect(find.text('Toggle Notes'), findsOneWidget);
      expect(find.text('Add Note'), findsOneWidget);
    });
  });
}
