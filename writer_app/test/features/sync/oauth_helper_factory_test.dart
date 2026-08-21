import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sync/services/apple_oauth_helper.dart';
import 'package:pellucid/features/sync/services/desktop_oauth_helper.dart';
import 'package:pellucid/features/sync/services/oauth_helper_factory.dart';

void main() {
  group('createOAuthHelper platform selection', () {
    final helper = createOAuthHelper(
      clientId: 'cid',
      clientSecret: 'secret',
      scopes: const ['https://www.googleapis.com/auth/drive.file'],
    );

    test('Apple platforms get the ASWebAuthenticationSession helper', () {
      // Guards the 2.4.5(i) fix: if macOS ever falls back to the loopback
      // helper it needs com.apple.security.network.server again, which App
      // Review's static scan rejects as an unused entitlement every time.
      if (!Platform.isIOS && !Platform.isMacOS) return;
      expect(helper, isA<AppleOAuthHelper>());
      expect(helper, isNot(isA<DesktopOAuthHelper>()));
    });

    test('Windows/Linux keep the loopback flow', () {
      if (Platform.isIOS || Platform.isMacOS) return;
      expect(helper, isA<DesktopOAuthHelper>());
      expect(helper, isNot(isA<AppleOAuthHelper>()));
    });
  });
}
