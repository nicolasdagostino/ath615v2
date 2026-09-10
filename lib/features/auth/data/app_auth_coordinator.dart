import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AppAuthState {
  initializing,
  refreshing,
  authenticated,
  definitivelyUnauthenticated,
}

class AppAuthCoordinator extends ChangeNotifier {
  AppAuthState _state = AppAuthState.initializing;
  bool _explicitLogout = false;

  AppAuthState get state => _state;
  bool get isTransitioning =>
      _state == AppAuthState.initializing || _state == AppAuthState.refreshing;

  void initializeFromSession(Session? session) {
    _transition(
      session == null
          ? AppAuthState.definitivelyUnauthenticated
          : AppAuthState.authenticated,
      reason: session == null ? 'initial_session_missing' : 'initial_session',
    );
  }

  void beginRefresh() {
    if (_state == AppAuthState.definitivelyUnauthenticated) return;
    _transition(AppAuthState.refreshing, reason: 'revalidation');
  }

  void markAuthenticated({String reason = 'auth_confirmed'}) {
    _explicitLogout = false;
    _transition(AppAuthState.authenticated, reason: reason);
  }

  void preserveAfterTransientFailure({required bool sessionPresent}) {
    if (sessionPresent) {
      markAuthenticated(reason: 'refresh_transient_session_preserved');
      return;
    }
    debugPrint('AUTH_STATE preserve refreshing reason=transient_session_null');
  }

  void markDefinitelyUnauthenticated({required String reason}) {
    _transition(AppAuthState.definitivelyUnauthenticated, reason: reason);
  }

  void beginExplicitLogout({String reason = 'explicit_logout'}) {
    _explicitLogout = true;
    markDefinitelyUnauthenticated(reason: reason);
  }

  void observeAuthEvent(AuthState event) {
    debugPrint(
      'AUTH_EVENT:${event.event.name} session=${event.session != null}',
    );
    if (event.session != null &&
        (event.event == AuthChangeEvent.initialSession ||
            event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.tokenRefreshed ||
            event.event == AuthChangeEvent.userUpdated ||
            event.event == AuthChangeEvent.passwordRecovery)) {
      markAuthenticated(reason: event.event.name);
      return;
    }
    if (event.event != AuthChangeEvent.signedOut) return;
    if (_explicitLogout || _state == AppAuthState.definitivelyUnauthenticated) {
      markDefinitelyUnauthenticated(reason: 'confirmed_signed_out');
      return;
    }
    debugPrint('AUTH_SIGNED_OUT_DURING_REFRESH');
    _transition(AppAuthState.refreshing, reason: 'signed_out_pending_review');
  }

  void _transition(AppAuthState next, {required String reason}) {
    final previous = _state;
    if (previous == next) return;
    _state = next;
    debugPrint('AUTH_STATE ${previous.name} -> ${next.name} reason=$reason');
    notifyListeners();
  }
}

final appAuthCoordinator = AppAuthCoordinator();
