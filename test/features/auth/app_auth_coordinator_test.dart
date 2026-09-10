import 'package:ath615v2/features/auth/data/app_auth_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
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
