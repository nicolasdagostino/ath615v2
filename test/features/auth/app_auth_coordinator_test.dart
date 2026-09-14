import 'dart:async';

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
    'signedOut without a definitive result stays transient after timeout',
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
        AuthRefreshResolution.transientFailure,
      );
      expect(coordinator.state, AppAuthState.refreshing);
    },
  );

  test(
    'slow refresh timeout stays transient and preserves authorization',
    () async {
      final coordinator = AppAuthCoordinator()
        ..markAuthenticated()
        ..beginRefresh(expectsSessionRefresh: true);
      final neverCompletes = Completer<void>();

      expect(
        await coordinator.resolveSessionRefresh(
          currentSession: () => null,
          refreshSession: () => neverCompletes.future,
          isDefinitiveFailure: (_) => false,
          timeout: Duration.zero,
        ),
        AuthRefreshResolution.transientFailure,
      );
      expect(coordinator.state, AppAuthState.refreshing);
    },
  );

  test(
    'coordinated refresh is single-flight across rapid resume events',
    () async {
      final coordinator = AppAuthCoordinator()
        ..markAuthenticated()
        ..beginRefresh(expectsSessionRefresh: true);
      final refreshCompleter = Completer<void>();
      Session? session;
      var refreshCalls = 0;

      Future<AuthRefreshResolution> resolve() =>
          coordinator.resolveSessionRefresh(
            currentSession: () => session,
            refreshSession: () {
              refreshCalls++;
              return refreshCompleter.future;
            },
            isDefinitiveFailure: (_) => false,
          );

      final first = resolve();
      final second = resolve();
      expect(refreshCalls, 1);

      session = _session();
      coordinator.observeAuthEvent(
        AuthState(AuthChangeEvent.tokenRefreshed, session),
      );
      refreshCompleter.complete();

      expect(await first, AuthRefreshResolution.refreshed);
      expect(await second, AuthRefreshResolution.refreshed);
      expect(coordinator.state, AppAuthState.authenticated);
    },
  );

  test(
    'intermediate signedOut then explicit refresh success never logs out',
    () async {
      final coordinator = AppAuthCoordinator()
        ..markAuthenticated()
        ..beginRefresh(expectsSessionRefresh: true);
      final refreshCompleter = Completer<void>();
      Session? session;

      final resolution = coordinator.resolveSessionRefresh(
        currentSession: () => session,
        refreshSession: () => refreshCompleter.future,
        isDefinitiveFailure: (_) => false,
      );
      coordinator.observeAuthEvent(
        const AuthState(AuthChangeEvent.signedOut, null),
      );
      expect(coordinator.state, AppAuthState.refreshing);

      session = _session();
      coordinator.observeAuthEvent(
        AuthState(AuthChangeEvent.tokenRefreshed, session),
      );
      refreshCompleter.complete();

      expect(await resolution, AuthRefreshResolution.refreshed);
      expect(coordinator.state, AppAuthState.authenticated);
    },
  );

  test('definitive refresh failure permits login', () async {
    final coordinator = AppAuthCoordinator()
      ..markAuthenticated()
      ..beginRefresh(expectsSessionRefresh: true);

    expect(
      await coordinator.resolveSessionRefresh(
        currentSession: () => null,
        refreshSession: () => Future<void>.error(StateError('revoked')),
        isDefinitiveFailure: (_) => true,
      ),
      AuthRefreshResolution.definitiveFailure,
    );
  });

  test('explicit logout wins over a late tokenRefreshed event', () {
    final coordinator = AppAuthCoordinator()
      ..markAuthenticated()
      ..beginRefresh(expectsSessionRefresh: true)
      ..beginExplicitLogout()
      ..observeAuthEvent(AuthState(AuthChangeEvent.tokenRefreshed, _session()));

    expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
  });

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
