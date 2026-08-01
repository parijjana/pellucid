import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sync/services/desktop_oauth_helper.dart';
import 'package:pellucid/features/sync/services/ios_oauth_helper.dart';
import 'package:pellucid/features/sync/services/oauth_helper_factory.dart';

void main() {
  group('createOAuthHelper platform selection', () {
    test('returns a DesktopOAuthHelper on non-iOS test host (loopback flow unchanged)', () {
      // The test runner always executes on the host desktop OS (macOS/Linux/
      // Windows CI), never as an actual iOS process, so Platform.isIOS is
      // false here — this exercises exactly the "desktop" branch that must
      // stay the shipping loopback flow.
      expect(Platform.isIOS, isFalse);

      final helper = createOAuthHelper(
        clientId: 'cid',
        clientSecret: 'secret',
        scopes: const ['email', 'profile'],
      );

      expect(helper, isA<DesktopOAuthHelper>());
      expect(helper, isNot(isA<IosOAuthHelper>()));
    });
  });
}
