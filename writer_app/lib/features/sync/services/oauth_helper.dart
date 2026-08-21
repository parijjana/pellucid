/// Shared contract for the platform-specific Google OAuth flows.
///
/// - Desktop (macOS/Windows/Linux) uses a localhost loopback HTTP server:
///   see [DesktopOAuthHelper] in `desktop_oauth_helper.dart`.
/// - iOS/iPadOS uses `ASWebAuthenticationSession` via a custom URL scheme:
///   see `AppleOAuthHelper` in `apple_oauth_helper.dart`.
///
/// Both implementations perform the full OAuth authorization-code + PKCE
/// (S256) dance with an anti-CSRF `state` value, and return the raw token
/// response from Google's token endpoint (keys like `access_token`,
/// `refresh_token`, `expires_in`) on success, or `null` on cancellation or
/// failure. Neither implementation ever exchanges a code whose `state`
/// doesn't match what it generated.
abstract class OAuthHelper {
  Future<Map<String, dynamic>?> authenticate();
}
