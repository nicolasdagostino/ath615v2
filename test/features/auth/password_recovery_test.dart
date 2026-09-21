import 'dart:async';
import 'dart:io';

import 'package:ath615v2/core/router/app_router.dart';
import 'package:ath615v2/core/router/deep_link_service.dart';
import 'package:ath615v2/features/auth/data/app_auth_coordinator.dart';
import 'package:ath615v2/features/auth/data/password_recovery_controller.dart';
import 'package:ath615v2/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppAuthCoordinator coordinator;
  late FakeRecoverySource source;
  late PasswordRecoveryController recovery;
  String? marker;
  final callback = Uri.parse('athletelab://reset-password?code=synthetic');
  setUp(() {
    marker = null;
    coordinator = AppAuthCoordinator()..markAuthenticated();
    source = FakeRecoverySource();
    recovery = PasswordRecoveryController(
      coordinator: coordinator,
      source: source,
      readMarker: () async => marker,
      writeMarker: (value) async => marker = value,
    );
  });

  test(
    'passwordRecovery is a routing requirement, never completed login',
    () async {
      recovery.observeAuthEvent(
        AuthState(AuthChangeEvent.passwordRecovery, session()),
      );
      expect(coordinator.state, AppAuthState.passwordRecoveryRequired);
      await Future<void>.delayed(Duration.zero);
      expect(marker, 'required');
      expect(recovery.ready, isTrue);
      expect(
        appAccessRedirect(
          authState: coordinator.state,
          path: '/app',
          isPublic: false,
          accessDestination: null,
        ),
        '/reset-password',
      );
    },
  );

  test(
    'code-only callback blocks before exchange and persists before session',
    () async {
      source.exchangeWork = Completer<void>();
      final work = recovery.handleCallback(callback);
      expect(coordinator.requiresPasswordRecovery, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(marker, 'pending');
      expect(source.exchanges, 1);
      source.exchangeWork!.complete();
      await work;
      expect(marker, 'required');
      expect(recovery.ready, isTrue);
    },
  );

  test(
    'cold start restores recovery before normal session initialization',
    () async {
      marker = 'required';
      await recovery.initialize();
      coordinator.initializeFromSession(session());
      expect(coordinator.requiresPasswordRecovery, isTrue);
      expect(recovery.ready, isTrue);
    },
  );

  test(
    'cold callback blocks a pre-existing normal session before first frame',
    () async {
      await recovery.initialize(initialUri: callback);
      coordinator.initializeFromSession(session());
      expect(coordinator.requiresPasswordRecovery, isTrue);
      expect(recovery.ready, isFalse);
      expect(marker, 'pending');
    },
  );

  test(
    'interrupted callback without confirmed recovery context fails closed',
    () async {
      marker = 'pending';
      await recovery.initialize();
      expect(source.hasSession, isFalse);
      expect(marker, isNull);
      expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
    },
  );

  test('all restored/protected destinations lose to recovery', () async {
    await recovery.handleCallback(callback);
    for (final route in [
      '/app',
      '/workout/one',
      '/gym-settings',
      '/membership',
      '/',
    ]) {
      expect(
        appAccessRedirect(
          authState: coordinator.state,
          path: route,
          isPublic: route == '/',
          accessDestination: '/gym-access-disabled',
        ),
        '/reset-password',
      );
      expect(
        authenticatedRoute(authState: coordinator.state, destination: route),
        '/reset-password',
      );
    }
  });

  test(
    'pending push is retained until successful password replacement',
    () async {
      final pending = PendingDeepLinkDestination()..remember('/workout/one');
      await recovery.handleCallback(callback);
      expect(
        authenticatedRoute(
          authState: coordinator.state,
          destination: '/workout/one',
        ),
        '/reset-password',
      );
      expect(
        await recovery.submit('abcdef', 'abcdef'),
        PasswordReplacementResult.success,
      );
      expect(pending.take(), '/workout/one');
      expect(pending.take(), isNull);
      expect(coordinator.state, AppAuthState.authenticated);
      expect(marker, isNull);
    },
  );

  test(
    'token refresh userUpdated revalidation and signedOut cannot lift recovery',
    () async {
      await recovery.handleCallback(callback);
      for (final event in [
        AuthChangeEvent.signedIn,
        AuthChangeEvent.tokenRefreshed,
        AuthChangeEvent.userUpdated,
        AuthChangeEvent.initialSession,
        AuthChangeEvent.signedOut,
      ]) {
        coordinator.observeAuthEvent(
          AuthState(
            event,
            event == AuthChangeEvent.signedOut ? null : session(),
          ),
        );
        coordinator.beginRefresh(expectsSessionRefresh: true);
        coordinator.markAuthenticated();
        coordinator.preserveAfterTransientFailure(sessionPresent: true);
        expect(coordinator.requiresPasswordRecovery, isTrue);
      }
    },
  );

  test('matching update succeeds only after server confirmation', () async {
    await recovery.handleCallback(callback);
    source.updateWork = Completer<void>();
    final work = recovery.submit('abcdef', 'abcdef');
    expect(coordinator.requiresPasswordRecovery, isTrue);
    expect(marker, 'required');
    coordinator.observeAuthEvent(
      AuthState(AuthChangeEvent.userUpdated, session()),
    );
    expect(coordinator.requiresPasswordRecovery, isTrue);
    source.updateWork!.complete();
    expect(await work, PasswordReplacementResult.success);
    expect(source.updates, 1);
    expect(marker, isNull);
    expect(coordinator.state, AppAuthState.authenticated);
  });

  test(
    'mismatch and empty/short passwords never send update requests',
    () async {
      await recovery.handleCallback(callback);
      expect(
        await recovery.submit('abcdef', 'different'),
        PasswordReplacementResult.mismatch,
      );
      expect(
        await recovery.submit('', ''),
        PasswordReplacementResult.invalidPassword,
      );
      expect(
        await recovery.submit('12345', '12345'),
        PasswordReplacementResult.invalidPassword,
      );
      expect(source.updates, 0);
    },
  );

  test(
    'network update failure retains recovery and persisted marker',
    () async {
      await recovery.handleCallback(callback);
      source.updateError = const SocketException('offline');
      expect(
        await recovery.submit('abcdef', 'abcdef'),
        PasswordReplacementResult.failed,
      );
      expect(coordinator.requiresPasswordRecovery, isTrue);
      expect(marker, 'required');
      expect(recovery.ready, isTrue);
    },
  );

  for (final error in [
    const FormatException('malformed'),
    const AuthException('expired', statusCode: '403'),
    const AuthException('consumed code', statusCode: '400'),
    const SocketException('offline'),
  ]) {
    test(
      'failed callback cannot reuse pre-existing session: ${error.runtimeType}',
      () async {
        source.exchangeError = error;
        await recovery.handleCallback(callback);
        expect(source.hasSession, isFalse);
        expect(recovery.ready, isFalse);
        expect(recovery.phase, RecoveryPhase.invalid);
        expect(marker, isNull);
        expect(
          appAccessRedirect(
            authState: coordinator.state,
            path: '/app',
            isPublic: false,
            accessDestination: null,
          ),
          '/login',
        );
      },
    );
  }

  test('failed local cleanup retains recovery routing lock', () async {
    source.exchangeError = const FormatException('invalid');
    source.logoutError = const SocketException('offline');
    await recovery.handleCallback(callback);
    expect(coordinator.requiresPasswordRecovery, isTrue);
    expect(recovery.ready, isFalse);
    source.logoutError = null;
    expect(await recovery.cancel(), isTrue);
    expect(marker, isNull);
  });

  test('multiple callbacks and submissions are single-flight', () async {
    source.exchangeWork = Completer<void>();
    final first = recovery.handleCallback(callback);
    final second = recovery.handleCallback(callback);
    await Future<void>.delayed(Duration.zero);
    expect(source.exchanges, 1);
    source.exchangeWork!.complete();
    await Future.wait([first, second]);
    await recovery.handleCallback(callback);
    expect(source.exchanges, 1);
    source.updateWork = Completer<void>();
    final update = recovery.submit('abcdef', 'abcdef');
    expect(
      await recovery.submit('abcdef', 'abcdef'),
      PasswordReplacementResult.unavailable,
    );
    source.updateWork!.complete();
    await update;
    expect(source.updates, 1);
  });

  test(
    'explicit cancellation waits for callback then removes its late session',
    () async {
      source.exchangeWork = Completer<void>();
      final callbackWork = recovery.handleCallback(callback);
      final cancel = recovery.cancel();
      await Future<void>.delayed(Duration.zero);
      source.exchangeWork!.complete();
      await callbackWork;
      expect(await cancel, isTrue);
      expect(source.hasSession, isFalse);
      expect(marker, isNull);
      coordinator.observeAuthEvent(
        AuthState(AuthChangeEvent.tokenRefreshed, session()),
      );
      expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
    },
  );

  test(
    'deleted user getUser invalidation clears recovery and routes Login',
    () async {
      marker = 'required';
      source.validationError = const AuthException(
        'User from sub claim in JWT does not exist',
        statusCode: '403',
      );
      await recovery.initialize();
      expect(source.hasSession, isFalse);
      expect(marker, isNull);
      expect(
        authenticatedRoute(authState: coordinator.state, destination: '/app'),
        '/login',
      );
    },
  );

  test('normal signIn and tokenRefreshed remain normal authentication', () {
    for (final event in [
      AuthChangeEvent.signedIn,
      AuthChangeEvent.tokenRefreshed,
    ]) {
      coordinator.observeAuthEvent(AuthState(event, session()));
      expect(coordinator.state, AppAuthState.authenticated);
    }
  });

  test(
    'intermediate session replacement updates readiness without unlocking recovery',
    () async {
      await recovery.handleCallback(callback);
      var notifications = 0;
      recovery.addListener(() => notifications++);
      source.hasSession = false;
      recovery.observeAuthEvent(
        const AuthState(AuthChangeEvent.signedOut, null),
      );
      expect(recovery.ready, isFalse);
      source.hasSession = true;
      recovery.observeAuthEvent(
        AuthState(AuthChangeEvent.tokenRefreshed, session()),
      );
      expect(recovery.ready, isTrue);
      expect(notifications, 2);
      expect(coordinator.requiresPasswordRecovery, isTrue);
      expect(marker, 'required');
    },
  );

  test('definitive invalidation beats an in-flight password update', () async {
    await recovery.handleCallback(callback);
    source.updateWork = Completer<void>();
    source.logoutWork = Completer<void>();
    final update = recovery.submit('abcdef', 'abcdef');
    source.validationError = const AuthException(
      'User not found',
      statusCode: '403',
    );
    final validation = recovery.revalidate();
    await Future<void>.delayed(Duration.zero);
    expect(recovery.phase, RecoveryPhase.invalid);
    source.updateWork!.complete();
    expect(await update, PasswordReplacementResult.unavailable);
    expect(coordinator.requiresPasswordRecovery, isTrue);
    source.logoutWork!.complete();
    await validation;
    expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
    expect(marker, isNull);
  });

  test(
    'explicit logout cleans up a session installed by a late callback',
    () async {
      source.exchangeWork = Completer<void>();
      final exchange = recovery.handleCallback(callback);
      coordinator.beginExplicitLogout();
      final logout = recovery.clearAfterExplicitLogout();
      await Future<void>.delayed(Duration.zero);
      source.exchangeWork!.complete();
      await exchange;
      await logout;
      expect(source.hasSession, isFalse);
      expect(marker, isNull);
      expect(coordinator.state, AppAuthState.definitivelyUnauthenticated);
    },
  );

  test('recovery logs contain no raw links or exception interpolation', () {
    for (final path in [
      'lib/core/router/deep_link_service.dart',
      'lib/features/auth/data/password_recovery_controller.dart',
    ]) {
      final text = File(path).readAsStringSync();
      expect(text, isNot(contains('debugPrint(')));
      expect(text, isNot(contains('print(')));
    }
  });

  testWidgets('real reset screen wins over restored app and submits once', (
    tester,
  ) async {
    // Create the async persistence queue inside the widget test clock.
    recovery = PasswordRecoveryController(
      coordinator: coordinator,
      source: source,
      readMarker: () async => marker,
      writeMarker: (value) async {
        marker = value;
      },
    );
    final initialization = recovery.handleCallback(callback);
    await tester.pump();
    await initialization;
    var appBuilds = 0;
    final router = GoRouter(
      initialLocation: '/app',
      refreshListenable: coordinator,
      redirect: (_, state) => appAccessRedirect(
        authState: coordinator.state,
        path: state.uri.path,
        isPublic: state.uri.path != '/app',
        accessDestination: null,
      ),
      routes: [
        GoRoute(
          path: '/app',
          builder: (_, _) {
            appBuilds++;
            return const Text('GYM');
          },
        ),
        GoRoute(path: '/', builder: (_, _) => const Text('VALIDATE ACCESS')),
        GoRoute(
          path: '/reset-password',
          builder: (_, _) => ResetPasswordScreen(controller: recovery),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(appBuilds, 0);
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('recovery-password')),
      'abcdef',
    );
    await tester.enterText(
      find.byKey(const ValueKey('recovery-confirmation')),
      'abcdef',
    );
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(source.updates, 1);
    expect(find.text('VALIDATE ACCESS'), findsOneWidget);
    expect(appBuilds, 0);
  });
}

Session session() => Session(
  accessToken: 'synthetic',
  tokenType: 'bearer',
  user: const User(
    id: 'synthetic',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-09-21T00:00:00Z',
  ),
);

class FakeRecoverySource implements RecoveryDataSource {
  @override
  bool hasSession = true;
  int exchanges = 0;
  int updates = 0;
  Object? exchangeError, updateError, validationError, logoutError;
  Completer<void>? exchangeWork, updateWork, logoutWork;
  @override
  Future<void> exchange(Uri uri) async {
    exchanges++;
    await exchangeWork?.future;
    if (exchangeError != null) throw exchangeError!;
    hasSession = true;
  }

  @override
  Future<void> updatePassword(String password) async {
    updates++;
    await updateWork?.future;
    if (updateError != null) throw updateError!;
  }

  @override
  Future<void> validateUser() async {
    if (validationError != null) throw validationError!;
  }

  @override
  Future<void> signOutLocally() async {
    await logoutWork?.future;
    if (logoutError != null) throw logoutError!;
    hasSession = false;
  }
}
