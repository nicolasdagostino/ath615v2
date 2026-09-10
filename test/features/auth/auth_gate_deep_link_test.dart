import 'dart:io';

import 'package:ath615v2/core/router/app_router.dart';
import 'package:ath615v2/features/auth/data/app_auth_coordinator.dart';
import 'package:ath615v2/features/auth/presentation/screens/auth_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initializing and refreshing preserve a protected route', () {
    for (final state in [AppAuthState.initializing, AppAuthState.refreshing]) {
      expect(
        appAccessRedirect(
          authState: state,
          path: '/app',
          isPublic: false,
          accessDestination: null,
        ),
        isNull,
      );
    }
  });

  test('restored or token-refreshed auth state keeps protected route', () {
    expect(
      appAccessRedirect(
        authState: AppAuthState.authenticated,
        path: '/app',
        isPublic: false,
        accessDestination: null,
      ),
      isNull,
    );
  });

  test('AuthGate only redirects while it still owns the root route', () {
    expect(shouldAuthGateRedirect('/'), isTrue);
    expect(shouldAuthGateRedirect('/membership'), isFalse);
    expect(shouldAuthGateRedirect('/reset-password'), isFalse);
    expect(shouldAuthGateRedirect('/help'), isFalse);
    expect(shouldAuthGateRedirect('/request-demo'), isFalse);
    expect(shouldAuthGateRedirect('/gym-settings'), isFalse);
  });

  test('AuthGate has no arbitrary authentication timeout', () {
    final gate = File(
      'lib/features/auth/presentation/screens/auth_gate.dart',
    ).readAsStringSync();
    expect(gate, isNot(contains('Duration(milliseconds: 1800)')));
  });

  test('router keeps disabled users outside protected destinations', () {
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    expect(router, contains("path: '/gym-access-disabled'"));
    for (final path in [
      '/app',
      '/membership',
      '/gym-settings',
      '/workout/workout-1',
    ]) {
      expect(
        appAccessRedirect(
          authState: AppAuthState.authenticated,
          path: path,
          isPublic: false,
          accessDestination: '/gym-access-disabled',
        ),
        '/gym-access-disabled',
      );
    }
  });

  test(
    'disabled route requires auth but remains available with valid auth',
    () {
      expect(
        appAccessRedirect(
          authState: AppAuthState.definitivelyUnauthenticated,
          path: '/gym-access-disabled',
          isPublic: false,
          accessDestination: '/gym-access-disabled',
        ),
        '/login',
      );
      expect(
        appAccessRedirect(
          authState: AppAuthState.authenticated,
          path: '/gym-access-disabled',
          isPublic: false,
          accessDestination: '/gym-access-disabled',
        ),
        isNull,
      );
    },
  );
}
