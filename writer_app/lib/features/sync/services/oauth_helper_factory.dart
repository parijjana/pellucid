import 'dart:io' show Platform;
import 'desktop_oauth_helper.dart';
import 'ios_oauth_helper.dart';
import 'oauth_helper.dart';

/// Picks the right [OAuthHelper] for the current platform.
///
/// - iOS/iPadOS: `ASWebAuthenticationSession` via [IosOAuthHelper] — a public
///   client secured by PKCE only, no [clientSecret].
/// - macOS/Windows/Linux: the existing, shipping localhost loopback flow via
///   [DesktopOAuthHelper] — unchanged.
OAuthHelper createOAuthHelper({
  required String clientId,
  required String clientSecret,
  required List<String> scopes,
}) {
  if (Platform.isIOS) {
    return IosOAuthHelper(clientId: clientId, scopes: scopes);
  }
  return DesktopOAuthHelper(
    clientId: clientId,
    clientSecret: clientSecret,
    scopes: scopes,
  );
}
