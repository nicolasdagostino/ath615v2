import 'package:ath615v2/features/auth/data/auth_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'session diagnostics include timing and booleans without credentials',
    () {
      final logs = <String>[];
      final diagnostics = AuthDiagnostics(sink: logs.add);
      final session = _session();

      diagnostics.logLifecycle(
        lifecycleState: 'resumed',
        session: session,
        coordinatorState: 'authenticated',
      );

      final log = logs.single;
      expect(log, contains(RegExp(r'^\d{4}-\d{2}-\d{2}T.*Z AUTH_LIFECYCLE')));
      expect(log, contains('resumeCycleId=1'));
      expect(log, contains('expiresAt='));
      expect(log, contains('now='));
      expect(log, contains('secondsToExpiry='));
      expect(log, contains('isExpired='));
      expect(log, contains('hasSession=YES'));
      expect(log, contains('hasRefreshToken=YES'));
      expect(log, isNot(contains('access-secret')));
      expect(log, isNot(contains('refresh-secret')));
      expect(log, isNot(contains('person@example.com')));
    },
  );

  test('auth failures expose status code and category but sanitize message', () {
    final logs = <String>[];
    final diagnostics = AuthDiagnostics(sink: logs.add);
    diagnostics.logAuthFailure(
      'AUTH_REFRESH_FAIL',
      AuthApiException(
        'Invalid Refresh Token: Refresh Token Already Been Used by person@example.com',
        statusCode: '400',
        code: 'refresh_token_already_used',
      ),
    );

    final log = logs.single;
    expect(log, contains('status=400'));
    expect(log, contains('code=refresh_token_already_used'));
    expect(log, contains('category=refresh_token_already_used'));
    expect(log, contains('message=refresh_token_already_used'));
    expect(log, isNot(contains('person@example.com')));
    expect(log, isNot(contains('Invalid Refresh Token')));
  });

  test(
    'signedOut and router logs contain safe session and storage snapshots',
    () async {
      SharedPreferences.setMockInitialValues({
        'sb-project-ref-auth-token': 'persisted-secret-session',
      });
      final logs = <String>[];
      final diagnostics = AuthDiagnostics(sink: logs.add);
      await diagnostics.initialize(
        supabaseUrl: 'https://project-ref.supabase.co',
        session: _session(),
        coordinatorState: 'initializing',
      );

      diagnostics.logAuthEvent(
        event: 'signedOut',
        stateBefore: 'refreshing',
        hasSessionBefore: true,
        hasRefreshTokenBefore: true,
        stateAfter: 'refreshing',
        sessionAfter: null,
        explicitLogout: false,
        refreshInProgress: true,
      );
      diagnostics.logRouter(
        event: 'ROUTER_LOGIN_REDIRECT',
        reason: 'definitively_unauthenticated',
        state: 'definitivelyUnauthenticated',
        hasSession: false,
      );

      expect(logs.join('\n'), contains('AUTH_STARTUP_SNAPSHOT'));
      expect(logs.join('\n'), contains('event=signedOut'));
      expect(logs.join('\n'), contains('explicitLogout=NO'));
      expect(logs.join('\n'), contains('refreshInProgress=YES'));
      expect(logs.join('\n'), contains('persistedSessionPresent=YES'));
      expect(logs.join('\n'), contains('ROUTER_LOGIN_REDIRECT'));
      expect(logs.join('\n'), isNot(contains('persisted-secret-session')));
    },
  );
}

Session _session() {
  final session = Session(
    accessToken: 'access-secret',
    refreshToken: 'refresh-secret',
    tokenType: 'bearer',
    user: const User(
      id: 'user-id',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      email: 'person@example.com',
      createdAt: '2026-09-10T00:00:00Z',
    ),
  );
  session.expiresAt =
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 60;
  return session;
}
