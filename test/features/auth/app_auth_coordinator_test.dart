import 'package:ath615v2/features/auth/data/app_auth_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'physical build 137 race preserves route until token refresh completes',
    () async {
      final coordinator = AppAuthCoordinator()
        ..markAuthenticated()
        ..beginRefresh(expectsSessionRefresh: true);
      Session? session;

      final resolution = coordinator.waitForSessionRefresh(
        currentSession: () => session,
      );
      var completed = false;
      resolution.then((_) => completed = true);
      coordinator.observeAuthEvent(
        const AuthState(AuthChangeEvent.signedOut, null),
      );
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.state, AppAuthState.refreshing);
      expect(coordinator.isSessionRefreshPending, isTrue);
      expect(completed, isFalse);

      session = _session();
      coordinator.observeAuthEvent(
        AuthState(AuthChangeEvent.tokenRefreshed, session),
      );

      expect(await resolution, AuthRefreshResolution.refreshed);
      expect(coordinator.state, AppAuthState.authenticated);
    },
  );

  test(
    'expired refresh timeout with an existing session stays transient',
    () async {
      final coordinator = AppAuthCoordinator()
        ..markAuthenticated()
        ..beginRefresh(expectsSessionRefresh: true);
      final expired = _session(expiresAt: 1);

      expect(
        await coordinator.waitForSessionRefresh(
          currentSession: () => expired,
          timeout: Duration.zero,
        ),
        AuthRefreshResolution.transientFailure,
      );
      expect(coordinator.state, AppAuthState.refreshing);
    },
  );

  test(
    'signedOut without recovery becomes definitive after bounded wait',
    () async {
      final coordinator = AppAuthCoordinator()
        ..markAuthenticated()
        ..beginRefresh(expectsSessionRefresh: true)
        ..observeAuthEvent(const AuthState(AuthChangeEvent.signedOut, null));

      expect(
        await coordinator.waitForSessionRefresh(
          currentSession: () => null,
          timeout: Duration.zero,
        ),
        AuthRefreshResolution.definitiveFailure,
      );
    },
  );

  test('refresh preserves authorization until its outcome is known', () {
    final coordinator = AppAuthCoordinator()
      ..markAuthenticated()
      ..beginRefresh();
    expect(coordinator.state, AppAuthState.refreshing);

    coordinator.observeAuthEvent(
      const AuthState(AuthChangeEvent.signedOut, null),
    );
    expect(coordinator.state, AppAuthState.refreshing);
  });

  test('refresh success restores authenticated state', () {
    final coordinator = AppAuthCoordinator()
      ..markAuthenticated()
      ..beginRefresh()
      ..markAuthenticated(reason: 'test_refresh_success');
    expect(coordinator.state, AppAuthState.authenticated);
  });

  test('transient refresh with a session preserves authentication', () {
    final coordinator = AppAuthCoordinator()
      ..markAuthenticated()
      ..beginRefresh()
      ..preserveAfterTransientFailure(sessionPresent: true);
    expect(coordinator.state, AppAuthState.authenticated);
  });

  test('explicit logout is definitive before signedOut arrives', () {
    final coordinator = AppAuthCoordinator()
      ..markAuthenticated()
      ..beginExplicitLogout();
    expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
    coordinator.observeAuthEvent(
      const AuthState(AuthChangeEvent.signedOut, null),
    );
    expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
  });

  test('confirmed deleted or revoked account is definitive', () {
    final coordinator = AppAuthCoordinator()..markAuthenticated();
    coordinator.markDefinitelyUnauthenticated(reason: 'deleted_user');
    expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
  });
}

Session _session({int? expiresAt}) {
  final session = Session(
    accessToken: 'test-access-token',
    tokenType: 'bearer',
    user: const User(
      id: 'user-id',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-09-10T00:00:00.000Z',
    ),
    expiresIn: 3600,
    refreshToken: 'test-refresh-token',
  );
  session.expiresAt =
      expiresAt ??
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
  return session;
}
