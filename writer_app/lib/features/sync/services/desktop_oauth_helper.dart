import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:url_launcher/url_launcher.dart';

class DesktopOAuthHelper {
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

  Future<Map<String, dynamic>?> authenticate() async {
    final completer = Completer<Map<String, dynamic>?>();
    final router = Router();
    
    HttpServer? server;
    int actualPort = port;

    // The route Google will redirect back to
    router.get('/', (Request request) async {
      final code = request.url.queryParameters['code'];
      if (code != null) {
        // Exchange code for tokens
        final tokens = await _exchangeCodeForTokens(code, actualPort);
        completer.complete(tokens);
        return Response.ok(
          '<h1>Pellucid Connected!</h1><p>You can close this tab and return to the app.</p>',
          headers: {'content-type': 'text/html'},
        );
      }
      completer.complete(null);
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
        'prompt=consent';

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

  Future<Map<String, dynamic>?> _exchangeCodeForTokens(String code, int actualPort) async {
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': 'http://localhost:$actualPort',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }
}
