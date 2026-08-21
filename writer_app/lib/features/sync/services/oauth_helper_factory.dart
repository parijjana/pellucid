import 'dart:io' show Platform;
import 'apple_oauth_helper.dart';
import 'desktop_oauth_helper.dart';
import 'oauth_helper.dart';

/// Picks the right [OAuthHelper] for the current platform.
///
/// - iOS/iPadOS/macOS: `ASWebAuthenticationSession` via [AppleOAuthHelper] — a
///   public client secured by PKCE only, no [clientSecret].
/// - Windows/Linux: the localhost loopback flow via [DesktopOAuthHelper].
///
/// macOS moved off the loopback flow in 1.1. The flow itself worked, but under
/// App Sandbox binding a listening socket — even on localhost — requires
/// `com.apple.security.network.server`, and App Review's automated scan is
/// static: it cannot see a `dart:io` `HttpServer.bind` inside the Flutter VM,
/// so it flags the entitlement as unused every single time (guideline
/// 2.4.5(i)). Rejected twice on that basis; a written justification did not
/// clear it. `ASWebAuthenticationSession` needs no listening socket, so the
/// entitlement is gone from `macos/Runner/*.entitlements` and the scan has
/// nothing to flag. Do not reintroduce either.
OAuthHelper createOAuthHelper({
  required String clientId,
  required String clientSecret,
  required List<String> scopes,
}) {
  if (Platform.isIOS || Platform.isMacOS) {
    return AppleOAuthHelper(clientId: clientId, scopes: scopes);
  }
  return DesktopOAuthHelper(
    clientId: clientId,
    clientSecret: clientSecret,
    scopes: scopes,
  );
}
