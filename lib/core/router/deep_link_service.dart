import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeepLinkService {
  DeepLinkService(this._router);

  final GoRouter _router;
  final AppLinks _appLinks = AppLinks();

  StreamSubscription<Uri>? _linkSub;

  Future<void> start() async {
    print('ATH615 DEEPLINK SERVICE STARTED');

    final initialUri = await _appLinks.getInitialLink();
    print('ATH615 INITIAL LINK => $initialUri');

    if (initialUri != null) {
      await _handle(initialUri);
    }

    _linkSub = _appLinks.uriLinkStream.listen(
      (uri) async {
        print('ATH615 STREAM LINK => $uri');
        await _handle(uri);
      },
      onError: (e) {
        print('ATH615 STREAM ERROR => $e');
      },
    );
  }

  Future<void> _handle(Uri uri) async {
    final raw = uri.toString();
    final lower = raw.toLowerCase();

    print('ATH615 DEEPLINK RAW => $raw');

    final isAuthLink =
        lower.contains('reset-password') ||
        lower.contains('type=invite') ||
        lower.contains('type=recovery') ||
        lower.contains('access_token') ||
        lower.contains('refresh_token') ||
        lower.contains('code=');

    print('ATH615 IS AUTH LINK => $isAuthLink');

    if (!isAuthLink) return;

    final fragmentParams = uri.fragment.isEmpty
        ? <String, String>{}
        : Uri.splitQueryString(uri.fragment);

    final queryParams = uri.queryParameters;

    final accessToken =
        queryParams['access_token'] ?? fragmentParams['access_token'];
    final refreshToken =
        queryParams['refresh_token'] ?? fragmentParams['refresh_token'];
    final code = queryParams['code'] ?? fragmentParams['code'];

    try {
      final auth = Supabase.instance.client.auth;

      if (refreshToken != null && refreshToken.isNotEmpty) {
        print('ATH615 DEEPLINK => setSession with refresh_token');
        await auth.setSession(refreshToken, accessToken: accessToken);
        print('ATH615 DEEPLINK SESSION OK');
      } else if (code != null && code.isNotEmpty) {
        print('ATH615 DEEPLINK => exchangeCodeForSession');
        await auth.exchangeCodeForSession(code);
        print('ATH615 DEEPLINK SESSION OK');
      } else {
        print('ATH615 DEEPLINK SESSION ERROR => no refresh_token or code');
      }
    } catch (e) {
      print('ATH615 DEEPLINK SESSION ERROR => $e');
    }

    _router.go('/reset-password');
  }

  Future<void> dispose() async {
    await _linkSub?.cancel();
  }
}
