import 'dart:io';

import 'package:ath615v2/core/router/app_router.dart';
import 'package:ath615v2/features/auth/presentation/screens/auth_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AuthGate only redirects while it still owns the root route', () {
    expect(shouldAuthGateRedirect('/'), isTrue);
    expect(shouldAuthGateRedirect('/membership'), isFalse);
    expect(shouldAuthGateRedirect('/reset-password'), isFalse);
    expect(shouldAuthGateRedirect('/help'), isFalse);
    expect(shouldAuthGateRedirect('/request-demo'), isFalse);
    expect(shouldAuthGateRedirect('/gym-settings'), isFalse);
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
          isAuthenticated: true,
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
          isAuthenticated: false,
          path: '/gym-access-disabled',
          isPublic: false,
          accessDestination: '/gym-access-disabled',
        ),
        '/login',
      );
      expect(
        appAccessRedirect(
          isAuthenticated: true,
          path: '/gym-access-disabled',
          isPublic: false,
          accessDestination: '/gym-access-disabled',
        ),
        isNull,
      );
    },
  );
}
