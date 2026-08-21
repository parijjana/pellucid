import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'oauth_helper.dart';

/// The existing, shipping desktop OAuth flow: binds a real localhost HTTP
/// server and redirects there. Unchanged behaviour — only now implements the
/// shared [OAuthHelper] contract so `google_drive_sync_service.dart` can pick
/// between this and the iOS ASWebAuthenticationSession flow without caring
/// which one it has.
class DesktopOAuthHelper implements OAuthHelper {
  final String clientId;
  final String clientSecret;
  final List<String> scopes;
  final int port;

  DesktopOAuthHelper({
    required this.clientId,
    required this.clientSecret,
    required this.scopes,
    this.port = 3000,
  });

  /// Unreserved characters allowed in a PKCE code_verifier (RFC 7636).
  static const String _unreserved =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// Generates a cryptographically random string of [length] using
  /// [Random.secure], drawn from the PKCE unreserved character set. Also used
  /// for the anti-CSRF `state` value.
  static String generateRandomString(int length) {
    final rand = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_unreserved[rand.nextInt(_unreserved.length)]);
    }
    return buffer.toString();
  }

  /// Computes the PKCE S256 challenge for [verifier]:
  /// base64url( SHA256(verifier) ) with `=` padding stripped.
  static String computeCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  @override
  Future<Map<String, dynamic>?> authenticate() async {
    final completer = Completer<Map<String, dynamic>?>();
    final router = Router();

    // Anti-CSRF state + PKCE pair for this authorization attempt.
    final state = generateRandomString(32);
    final codeVerifier = generateRandomString(64);
    final codeChallenge = computeCodeChallenge(codeVerifier);

    HttpServer? server;
    int actualPort = port;

    // The route Google will redirect back to.
    router.get('/', (Request request) async {
      final returnedState = request.url.queryParameters['state'];
      final code = request.url.queryParameters['code'];

      // Reject anything whose state does not exactly match what we generated
      // (auth-code injection / login-CSRF protection). Never exchange the code.
      if (returnedState != state) {
        if (!completer.isCompleted) completer.complete(null);
        return Response.forbidden(
          '<h1>Sign-in could not be verified</h1>'
          '<p>You can close this tab and try again from the app.</p>',
          headers: {'content-type': 'text/html'},
        );
      }

      if (code != null) {
        // Exchange code for tokens (with PKCE verifier).
        final tokens =
            await _exchangeCodeForTokens(code, actualPort, codeVerifier);
        if (!completer.isCompleted) completer.complete(tokens);
        return Response.ok(
          '<h1>Pellucid Connected!</h1><p>You can close this tab and return to the app.</p>',
          headers: {'content-type': 'text/html'},
        );
      }

      if (!completer.isCompleted) completer.complete(null);
      return Response.notFound('No code found');
    });

    try {
      server = await io.serve(router.call, 'localhost', actualPort);
    } catch (_) {
      // Fallback to random free port
      server = await io.serve(router.call, 'localhost', 0);
      actualPort = server.port;
    }

    // Construct the auth URL
    final authUrl = 'https://accounts.google.com/o/oauth2/v2/auth?'
        'client_id=$clientId&'
        'redirect_uri=http://localhost:$actualPort&'
        'response_type=code&'
        'scope=${scopes.join('%20')}&'
        'access_type=offline&'
        'prompt=consent&'
        'state=$state&'
        'code_challenge=$codeChallenge&'
        'code_challenge_method=S256';

    try {
      await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      server.close();
      return null;
    }

    // Wait for the server to catch the code or timeout
    final result = await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => null,
    );

    server.close();
    return result;
  }

  Future<Map<String, dynamic>?> _exchangeCodeForTokens(
      String code, int actualPort, String codeVerifier) async {
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': 'http://localhost:$actualPort',
        'code_verifier': codeVerifier,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }
}
