import 'dart:convert';
import 'dart:io';

import 'package:ath615v2/features/auth/data/app_auth_coordinator.dart';
import 'package:ath615v2/features/auth/data/password_recovery_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Exercises the installed SDK over local HTTP. No production credentials/data.
void main() {
  late HttpServer server;
  late SupabaseClient client;
  late PasswordRecoveryController recovery;
  late AppAuthCoordinator coordinator;
  late Map<String, dynamic> session;
  const user = {
    'id': 'synthetic-user',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'aud': 'authenticated',
    'created_at': '2026-09-21T00:00:00Z',
  };
  String? marker;
  var rejectCode = false;
  var deletedUser = false;
  var updates = 0;
  setUp(() async {
    marker = null;
    rejectCode = false;
    deletedUser = false;
    updates = 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    session = {
      'access_token':
          '${part({'alg': 'HS256'})}.${part({'exp': now + 3600, 'iat': now, 'sub': 'synthetic-user'})}.c3ludGhldGlj',
      'refresh_token': 'synthetic-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': now + 3600,
      'user': user,
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/token')) {
        request.response.statusCode = rejectCode ? 400 : 200;
        request.response.write(
          jsonEncode(
            rejectCode
                ? {'error_code': 'bad_code_verifier', 'msg': 'Invalid code'}
                : session,
          ),
        );
      } else if (request.uri.path.endsWith('/user')) {
        if (request.method == 'PUT') updates++;
        request.response.statusCode = deletedUser ? 403 : 200;
        request.response.write(
          jsonEncode(
            deletedUser
                ? {
                    'error_code': 'user_not_found',
                    'msg': 'User from sub claim in JWT does not exist',
                  }
                : user,
          ),
        );
      } else if (request.uri.path.endsWith('/logout')) {
        request.response.statusCode = 204;
      } else {
        request.response.write('{}');
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-anon',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: _SdkStorage(),
      ),
    );
    coordinator = AppAuthCoordinator();
    recovery = PasswordRecoveryController(
      coordinator: coordinator,
      source: SupabaseRecoveryDataSource(client),
      readMarker: () async => marker,
      writeMarker: (value) async {
        marker = value;
      },
    );
    final subscription = client.auth.onAuthStateChange.listen(
      recovery.observeAuthEvent,
    );
    addTearDown(subscription.cancel);
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'SDK PKCE code-only exchange emits passwordRecovery and requires updateUser',
    () async {
      await client.auth.resetPasswordForEmail(
        'synthetic@test.invalid',
        redirectTo: 'athletelab://reset-password',
      );
      final events = <AuthChangeEvent>[];
      final subscription = client.auth.onAuthStateChange.listen(
        (event) => events.add(event.event),
      );
      await recovery.handleCallback(
        Uri.parse('athletelab://reset-password?code=synthetic'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, contains(AuthChangeEvent.passwordRecovery));
      expect(coordinator.requiresPasswordRecovery, isTrue);
      expect(recovery.ready, isTrue);
      expect(marker, 'required');
      expect(
        await recovery.submit('abcdef', 'abcdef'),
        PasswordReplacementResult.success,
      );
      expect(updates, 1);
      expect(coordinator.state, AppAuthState.authenticated);
      expect(marker, isNull);
      await subscription.cancel();
    },
  );

  test(
    'invalid code cannot retain an existing authenticated SDK session',
    () async {
      await client.auth.setInitialSession(jsonEncode(session));
      await client.auth.resetPasswordForEmail('synthetic@test.invalid');
      rejectCode = true;
      await recovery.handleCallback(
        Uri.parse('athletelab://reset-password?code=invalid'),
      );
      expect(client.auth.currentSession, isNull);
      expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
      expect(recovery.ready, isFalse);
    },
  );

  test(
    'successful non-recovery PKCE exchange cannot masquerade as recovery',
    () async {
      await client.auth.signInWithOtp(email: 'synthetic@test.invalid');
      await recovery.handleCallback(
        Uri.parse('athletelab://reset-password?code=synthetic'),
      );
      expect(client.auth.currentSession, isNull);
      expect(recovery.phase, RecoveryPhase.invalid);
      expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
    },
  );

  test(
    'legacy recovery validates user and cannot use signedIn to bypass lock',
    () async {
      final uri = Uri(
        scheme: 'athletelab',
        host: 'reset-password',
        fragment: Uri(
          queryParameters: {
            'type': 'recovery',
            'access_token': session['access_token'] as String,
            'refresh_token': session['refresh_token'] as String,
          },
        ).query,
      );
      await recovery.handleCallback(uri);
      expect(recovery.ready, isTrue);
      expect(coordinator.requiresPasswordRecovery, isTrue);
    },
  );

  test(
    'deleted Auth user rejection invalidates exchanged recovery session',
    () async {
      await client.auth.resetPasswordForEmail('synthetic@test.invalid');
      deletedUser = true;
      await recovery.handleCallback(
        Uri.parse('athletelab://reset-password?code=synthetic'),
      );
      expect(client.auth.currentSession, isNull);
      expect(marker, isNull);
      expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
    },
  );

  for (final suffix in [
    '',
    '?error=access_denied&error_code=otp_expired',
    '#type=recovery',
    '?code=',
  ]) {
    test('malformed or expired callback fails closed: $suffix', () async {
      await client.auth.setInitialSession(jsonEncode(session));
      await recovery.handleCallback(
        Uri.parse('athletelab://reset-password$suffix'),
      );
      expect(client.auth.currentSession, isNull);
      expect(recovery.ready, isFalse);
      expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
    });
  }
}

// SDK-owned ephemeral test storage; production recovery state never stores PKCE.
class _SdkStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}
