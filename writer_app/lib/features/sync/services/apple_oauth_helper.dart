import 'dart:convert';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'desktop_oauth_helper.dart';
import 'oauth_helper.dart';

/// iOS/iPadOS Google OAuth flow using `ASWebAuthenticationSession`
/// (via `flutter_web_auth_2`) instead of the desktop localhost-loopback
/// server, which iOS cannot bind/receive a redirect to.
///
/// Google's "iOS" OAuth client type is a *public* client: there is no client
/// secret, and the mandated redirect URI is the reverse-DNS form of the
/// client id (`com.googleusercontent.apps.<id>:/oauthredirect`), which is
/// also the custom URL scheme that must be registered in
/// `ios/Runner/Info.plist` under `CFBundleURLTypes`. PKCE (S256) is what
/// secures the exchange in place of a secret.
///
/// Reuses [DesktopOAuthHelper.generateRandomString] and
/// [DesktopOAuthHelper.computeCodeChallenge] (state/PKCE helpers hardened and
/// tested against the RFC 7636 vector in commit 06321bb) rather than
/// reimplementing them.
class AppleOAuthHelper implements OAuthHelper {
  final String clientId;
  final List<String> scopes;

  AppleOAuthHelper({
    required this.clientId,
    required this.scopes,
  });

  /// Derives the reverse-DNS custom URL scheme Google's iOS OAuth clients
  /// require for their redirect URI, e.g.
  /// `123-abc.apps.googleusercontent.com` -> `com.googleusercontent.apps.123-abc`.
  ///
  /// This value MUST exactly match a `CFBundleURLSchemes` entry registered in
  /// `ios/Runner/Info.plist`, or `ASWebAuthenticationSession` will never be
  /// able to hand the redirect back to the app.
  static String reversedScheme(String clientId) {
    const suffix = '.apps.googleusercontent.com';
    if (clientId.endsWith(suffix)) {
      final prefix = clientId.substring(0, clientId.length - suffix.length);
      return 'com.googleusercontent.apps.$prefix';
    }
    // Fallback for a client id that doesn't match Google's usual shape:
    // naive reverse-DNS (swap and reverse the dot-separated labels).
    return clientId.split('.').reversed.join('.');
  }

  /// The full redirect URI passed to Google and awaited by
  /// `ASWebAuthenticationSession`.
  static String redirectUri(String clientId) =>
      '${reversedScheme(clientId)}:/oauthredirect';

  @override
  Future<Map<String, dynamic>?> authenticate() async {
    final state = DesktopOAuthHelper.generateRandomString(32);
    final codeVerifier = DesktopOAuthHelper.generateRandomString(64);
    final codeChallenge = DesktopOAuthHelper.computeCodeChallenge(codeVerifier);

    final scheme = reversedScheme(clientId);
    final redirect = redirectUri(clientId);

    final authUrl = 'https://accounts.google.com/o/oauth2/v2/auth?'
        'client_id=$clientId&'
        'redirect_uri=${Uri.encodeComponent(redirect)}&'
        'response_type=code&'
        'scope=${scopes.join('%20')}&'
        'access_type=offline&'
        'prompt=consent&'
        'state=$state&'
        'code_challenge=$codeChallenge&'
        'code_challenge_method=S256';

    String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: scheme,
      );
    } catch (_) {
      // User cancelled the sheet, or ASWebAuthenticationSession errored.
      return null;
    }

    final returnedUri = Uri.parse(result);
    final returnedState = returnedUri.queryParameters['state'];
    final code = returnedUri.queryParameters['code'];

    // Reject anything whose state does not exactly match what we generated
    // (auth-code injection / login-CSRF protection). Never exchange the code.
    if (returnedState != state || code == null) {
      return null;
    }

    return _exchangeCodeForTokens(code, redirect, codeVerifier);
  }

  Future<Map<String, dynamic>?> _exchangeCodeForTokens(
      String code, String redirectUri, String codeVerifier) async {
    // No client_secret: iOS OAuth clients are public clients (RFC 8252).
    // PKCE (code_verifier) is what proves this exchange came from the party
    // that started the authorization request.
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }
}
