import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sync/services/desktop_oauth_helper.dart';

void main() {
  group('DesktopOAuthHelper PKCE + state (OAuth hardening)', () {
    test('computeCodeChallenge matches the RFC 7636 S256 test vector', () {
      // RFC 7636 Appendix B.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expectedChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
      expect(DesktopOAuthHelper.computeCodeChallenge(verifier),
          equals(expectedChallenge));
    });

    test('code challenge is base64url without padding (no + / =)', () {
      final challenge = DesktopOAuthHelper.computeCodeChallenge(
          DesktopOAuthHelper.generateRandomString(64));
      expect(challenge.contains('='), isFalse);
      expect(challenge.contains('+'), isFalse);
      expect(challenge.contains('/'), isFalse);
    });

    test('generateRandomString: correct length, PKCE-unreserved charset', () {
      final s = DesktopOAuthHelper.generateRandomString(64);
      expect(s.length, equals(64));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(s), isTrue);
    });

    test('generateRandomString produces unique values (state/verifier)', () {
      final values = List.generate(
          50, (_) => DesktopOAuthHelper.generateRandomString(32));
      expect(values.toSet().length, equals(50));
    });
  });
}
