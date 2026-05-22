import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/sync_status_cloud.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';

void main() {
  final WriterTheme testTheme = WriterTheme.presets[0];

  group('SyncStatusCloud Widget Tests', () {
    testWidgets('renders correctly when Not Logged In', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusCloud(
              isLoggedIn: false,
              status: SyncStatus.idle,
              theme: testTheme,
            ),
          ),
        ),
      );

      final customPaintFinder = find.descendant(
        of: find.byType(SyncStatusCloud),
        matching: find.byType(CustomPaint),
      );
      expect(customPaintFinder, findsOneWidget);

      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      final painter = customPaint.painter as CloudStatusPainter;
      expect(painter.isLoggedIn, isFalse);
      expect(painter.status, SyncStatus.idle);
    });

    testWidgets('renders correctly when Logged In and Synced (idle/success)', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusCloud(
              isLoggedIn: true,
              status: SyncStatus.success,
              theme: testTheme,
            ),
          ),
        ),
      );

      final customPaintFinder = find.descendant(
        of: find.byType(SyncStatusCloud),
        matching: find.byType(CustomPaint),
      );
      expect(customPaintFinder, findsOneWidget);

      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      final painter = customPaint.painter as CloudStatusPainter;
      expect(painter.isLoggedIn, isTrue);
      expect(painter.status, SyncStatus.success);
    });

    testWidgets('renders correctly when Sync Failure (error)', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusCloud(
              isLoggedIn: true,
              status: SyncStatus.error,
              theme: testTheme,
            ),
          ),
        ),
      );

      final customPaintFinder = find.descendant(
        of: find.byType(SyncStatusCloud),
        matching: find.byType(CustomPaint),
      );
      expect(customPaintFinder, findsOneWidget);

      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      final painter = customPaint.painter as CloudStatusPainter;
      expect(painter.isLoggedIn, isTrue);
      expect(painter.status, SyncStatus.error);
    });

    testWidgets('animates and operates controller correctly when Syncing', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusCloud(
              isLoggedIn: true,
              status: SyncStatus.syncing,
              theme: testTheme,
            ),
          ),
        ),
      );

      final customPaintFinder = find.descendant(
        of: find.byType(SyncStatusCloud),
        matching: find.byType(CustomPaint),
      );
      expect(customPaintFinder, findsOneWidget);

      // Verify animation controller repeats (which pumps continuous animation frames)
      await tester.pump(const Duration(milliseconds: 500));
      
      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      final painter = customPaint.painter as CloudStatusPainter;
      expect(painter.isLoggedIn, isTrue);
      expect(painter.status, SyncStatus.syncing);
      expect(painter.animValue, isNot(0.0));

      // Transition to idle to stop animation before test ends
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusCloud(
              isLoggedIn: true,
              status: SyncStatus.idle,
              theme: testTheme,
            ),
          ),
        ),
      );
      await tester.pump();
    });

    testWidgets('updates didUpdateWidget state cleanly between syncing and idle', (WidgetTester tester) async {
      // Start in Idle
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusCloud(
              isLoggedIn: true,
              status: SyncStatus.idle,
              theme: testTheme,
            ),
          ),
        ),
      );

      final customPaintFinder = find.descendant(
        of: find.byType(SyncStatusCloud),
        matching: find.byType(CustomPaint),
      );

      var customPaint = tester.widget<CustomPaint>(customPaintFinder);
      var painter = customPaint.painter as CloudStatusPainter;
      expect(painter.status, SyncStatus.idle);
      expect(painter.animValue, 0.0);

      // Update to Syncing
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusCloud(
              isLoggedIn: true,
              status: SyncStatus.syncing,
              theme: testTheme,
            ),
          ),
        ),
      );

      // Pump to let the frame trigger animation loop
      await tester.pump(const Duration(milliseconds: 100));

      customPaint = tester.widget<CustomPaint>(customPaintFinder);
      painter = customPaint.painter as CloudStatusPainter;
      expect(painter.status, SyncStatus.syncing);

      // Update back to Success (idle)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusCloud(
              isLoggedIn: true,
              status: SyncStatus.success,
              theme: testTheme,
            ),
          ),
        ),
      );

      // Settle animation
      await tester.pump();

      customPaint = tester.widget<CustomPaint>(customPaintFinder);
      painter = customPaint.painter as CloudStatusPainter;
      expect(painter.status, SyncStatus.success);
    });
  });
}
