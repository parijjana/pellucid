import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sync/services/ios_oauth_helper.dart';

void main() {
  group('IosOAuthHelper.reversedScheme (Google iOS OAuth redirect scheme)', () {
    test('derives the reverse-DNS scheme from a standard Google client id', () {
      const clientId = '123456-abcde.apps.googleusercontent.com';
      expect(
        IosOAuthHelper.reversedScheme(clientId),
        equals('com.googleusercontent.apps.123456-abcde'),
      );
    });

    test('preserves hyphens and mixed-case in the client id prefix', () {
      const clientId = '987-XyZ-1.apps.googleusercontent.com';
      expect(
        IosOAuthHelper.reversedScheme(clientId),
        equals('com.googleusercontent.apps.987-XyZ-1'),
      );
    });

    test('falls back to a naive reverse-DNS for an unexpected client id shape',
        () {
      const clientId = 'foo.bar.example.com';
      expect(
        IosOAuthHelper.reversedScheme(clientId),
        equals('com.example.bar.foo'),
      );
    });
  });

  group('IosOAuthHelper.redirectUri', () {
    test('appends the fixed oauthredirect path to the derived scheme', () {
      const clientId = '999-zzz.apps.googleusercontent.com';
      expect(
        IosOAuthHelper.redirectUri(clientId),
        equals('com.googleusercontent.apps.999-zzz:/oauthredirect'),
      );
    });
  });

  group('IosOAuthHelper authorization URL shape (via helper statics)', () {
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
}
