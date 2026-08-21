// Description: Tests for the shared usesCommandModifier keyboard-shortcut
// predicate in lib/core/platform_context.dart.
//
// NOTE: `flutter test` always runs on a desktop host (macOS/Linux/Windows),
// never on iOS, so we cannot exercise the `Platform.isIOS` branch here the
// way a real iPad run would. What we CAN verify on every host is that the
// predicate is defined purely in terms of Platform.isMacOS / Platform.isIOS
// (no accidental extra conditions), and that it is strictly broader than
// (never false when) the old macOS-only check used to be — i.e. the fix
// can only ADD platforms (iOS) to the set that gets Cmd-based shortcuts,
// never remove macOS. See shortcuts_test.dart / formatting_shortcuts_test.dart
// for the widget-level shortcut-activation tests that exercise this on the
// current host platform.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/core/platform_context.dart';
import 'package:provider/provider.dart';

void main() {
  group('PointerTypeNotifier', () {
    test('starts with hasPointer false and latches true on first hover, never reverting', () {
      final notifier = PointerTypeNotifier();
      expect(notifier.hasPointer, isFalse);

      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      notifier.onPointerHover(const PointerHoverEvent());
      expect(notifier.hasPointer, isTrue);
      expect(notifyCount, 1);

      // A second hover is a no-op: already latched, must not notify again.
      notifier.onPointerHover(const PointerHoverEvent());
      expect(notifier.hasPointer, isTrue);
      expect(notifyCount, 1);
    });
  });

  group('hasPointerOrDefault', () {
    testWidgets('defaults to true when no PointerTypeNotifier is in the tree', (tester) async {
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = hasPointerOrDefault(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(result, isTrue,
          reason: 'Widget trees without the app\'s real provider set (most '
              'existing widget tests) must keep the pre-existing dim-until-'
              'hover behavior instead of throwing ProviderNotFoundException.');
    });

    testWidgets('reflects a real PointerTypeNotifier when one is registered', (tester) async {
      final notifier = PointerTypeNotifier();
      late bool Function() readResult;

      await tester.pumpWidget(
        ChangeNotifierProvider<PointerTypeNotifier>.value(
          value: notifier,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                final result = hasPointerOrDefault(context);
                readResult = () => result;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(readResult(), isFalse);

      notifier.onPointerHover(const PointerHoverEvent());
      await tester.pump();

      expect(readResult(), isTrue);
    });
  });

  group('isTouchWithoutPointer', () {
    testWidgets('is always false on a non-touch host regardless of hasPointer, so desktop never sees the touch-resting treatment', (tester) async {
      // flutter test always runs on a desktop host (see file header note), so
      // isTouchPlatform is false here. This asserts the platform
      // short-circuit actually short-circuits: even with a
      // PointerTypeNotifier registered and hasPointer still false (as it is
      // at cold launch, before any hover), isTouchWithoutPointer must be
      // false on a non-touch host — never true — because desktop must be
      // completely unaffected by this signal.
      final notifier = PointerTypeNotifier();
      late bool Function() readResult;

      await tester.pumpWidget(
        ChangeNotifierProvider<PointerTypeNotifier>.value(
          value: notifier,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                final result = isTouchWithoutPointer(context);
                readResult = () => result;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(notifier.hasPointer, isFalse);
      expect(readResult(), isFalse);
      expect(isTouchPlatform, isFalse);
    });
  });

  group('usesCommandModifier', () {
    test('matches macOS-or-iOS, never web', () {
      final bool expected =
          !kIsWeb && (Platform.isMacOS || Platform.isIOS);
      expect(usesCommandModifier, expected);
    });

    test('is true whenever the old macOS-only check was true (superset, not replacement)', () {
      final bool oldMacOnlyCheck = !kIsWeb && Platform.isMacOS;
      if (oldMacOnlyCheck) {
        expect(usesCommandModifier, isTrue,
            reason: 'usesCommandModifier must remain true for every '
                'platform the old isMac check covered (macOS) — this is '
                'an additive fix for iOS, not a behavior change on macOS.');
      }
    });

    test('agrees with isTouchPlatform on Android (Ctrl-style, not Cmd-style)', () {
      // Android is touch-first (isTouchPlatform) but uses Ctrl, not Cmd —
      // usesCommandModifier must NOT conflate "touch platform" with "Command
      // modifier platform". iOS is the only touch platform where they agree.
      if (!kIsWeb && Platform.isAndroid) {
        expect(usesCommandModifier, isFalse);
        expect(isTouchPlatform, isTrue);
      }
    });
  });
}
