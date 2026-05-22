import 'dart:async';
import 'dart:convert';
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

    // The route Google will redirect back to
    router.get('/', (Request request) async {
      final code = request.url.queryParameters['code'];
      if (code != null) {
        // Exchange code for tokens
        final tokens = await _exchangeCodeForTokens(code);
        completer.complete(tokens);
        return Response.ok(
          '<h1>Pellucid Connected!</h1><p>You can close this tab and return to the app.</p>',
          headers: {'content-type': 'text/html'},
        );
      }
      completer.complete(null);
      return Response.notFound('No code found');
    });

    final server = await io.serve(router.call, 'localhost', port);
    
    // Construct the auth URL
    final authUrl = 'https://accounts.google.com/o/oauth2/v2/auth?'
        'client_id=$clientId&'
        'redirect_uri=http://localhost:$port&'
        'response_type=code&'
        'scope=${scopes.join('%20')}';

    if (await canLaunchUrl(Uri.parse(authUrl))) {
      await launchUrl(Uri.parse(authUrl));
    } else {
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

  Future<Map<String, dynamic>?> _exchangeCodeForTokens(String code) async {
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': 'http://localhost:$port',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }
}
