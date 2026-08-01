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
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/core/platform_context.dart';

void main() {
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
