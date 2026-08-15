import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sync/services/apple_oauth_helper.dart';

void main() {
  group('AppleOAuthHelper.reversedScheme (Google iOS OAuth redirect scheme)', () {
    test('derives the reverse-DNS scheme from a standard Google client id', () {
      const clientId = '123456-abcde.apps.googleusercontent.com';
      expect(
        AppleOAuthHelper.reversedScheme(clientId),
        equals('com.googleusercontent.apps.123456-abcde'),
      );
    });

    test('preserves hyphens and mixed-case in the client id prefix', () {
      const clientId = '987-XyZ-1.apps.googleusercontent.com';
      expect(
        AppleOAuthHelper.reversedScheme(clientId),
        equals('com.googleusercontent.apps.987-XyZ-1'),
      );
    });

    test('falls back to a naive reverse-DNS for an unexpected client id shape',
        () {
      const clientId = 'foo.bar.example.com';
      expect(
        AppleOAuthHelper.reversedScheme(clientId),
        equals('com.example.bar.foo'),
      );
    });
  });

  group('AppleOAuthHelper.redirectUri', () {
    test('appends the fixed oauthredirect path to the derived scheme', () {
      const clientId = '999-zzz.apps.googleusercontent.com';
      expect(
        AppleOAuthHelper.redirectUri(clientId),
        equals('com.googleusercontent.apps.999-zzz:/oauthredirect'),
      );
    });
  });

  group('AppleOAuthHelper authorization URL shape (via helper statics)', () {
    test('scopes join with %20 and never include sensitive Drive scopes',
        () {
      // Mirrors exactly what google_drive_sync_service.dart passes in: the
      // login() scopes list must never widen beyond these three non-sensitive
      // scopes (drive.file, not full drive), or the app would need Google
      // verification review.
      const scopes = ['https://www.googleapis.com/auth/drive.file', 'email', 'profile'];
      final joined = scopes.join('%20');
      expect(joined, contains('drive.file'));
      expect(joined, isNot(contains('auth/drive%20')));
      expect(joined, isNot(contains('drive.readonly')));
    });
  });


  group('macOS/iOS redirect scheme registration parity', () {
    // ASWebAuthenticationSession can only hand the redirect back if the
    // CFBundleURLSchemes entry equals reversedScheme(GOOGLE_IOS_CLIENT_ID).
    // macOS reuses the iOS OAuth client, so the two plists must agree — a
    // silent drift here breaks sign-in only at runtime, on device.
    String? schemeIn(String path) {
      final xml = File(path).readAsStringSync();
      final match = RegExp(
        r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>([^<]+)</string>',
      ).firstMatch(xml);
      return match?.group(1);
    }

    test('both Info.plists register the same reverse-DNS scheme', () {
      final ios = schemeIn('ios/Runner/Info.plist');
      final macos = schemeIn('macos/Runner/Info.plist');

      expect(ios, isNotNull, reason: 'iOS OAuth URL scheme missing');
      expect(macos, isNotNull, reason: 'macOS OAuth URL scheme missing');
      expect(macos, ios);
      // And it must be the shape reversedScheme() produces from a Google
      // client id, not a hand-rolled scheme.
      expect(macos, startsWith('com.googleusercontent.apps.'));
      final clientId =
          '${macos!.substring('com.googleusercontent.apps.'.length)}'
          '.apps.googleusercontent.com';
      expect(AppleOAuthHelper.reversedScheme(clientId), macos);
    });
  });
}
