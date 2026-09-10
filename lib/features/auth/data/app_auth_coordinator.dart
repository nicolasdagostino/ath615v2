import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_diagnostics.dart';

enum AppAuthState {
  initializing,
  refreshing,
  authenticated,
  definitivelyUnauthenticated,
}

class AppAuthCoordinator extends ChangeNotifier {
  AppAuthState _state = AppAuthState.initializing;
  bool _explicitLogout = false;
  bool _lastHasSession = false;
  bool _lastHasRefreshToken = false;

  AppAuthState get state => _state;
  bool get hasKnownSession => _lastHasSession;
  bool get isTransitioning =>
      _state == AppAuthState.initializing || _state == AppAuthState.refreshing;

  void initializeFromSession(Session? session) {
    _lastHasSession = session != null;
    _lastHasRefreshToken = session?.refreshToken?.isNotEmpty == true;
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
    authDiagnostics.logTransition(
      from: _state.name,
      to: _state.name,
      reason: 'transient_session_null',
    );
  }

  void markDefinitelyUnauthenticated({required String reason}) {
    _transition(AppAuthState.definitivelyUnauthenticated, reason: reason);
  }

  void beginExplicitLogout({String reason = 'explicit_logout'}) {
    _explicitLogout = true;
    markDefinitelyUnauthenticated(reason: reason);
  }

  void observeAuthEvent(AuthState event) {
    final stateBefore = _state;
    final hasSessionBefore = _lastHasSession;
    final hasRefreshTokenBefore = _lastHasRefreshToken;
    final explicitLogout = _explicitLogout;
    final refreshInProgress = _state == AppAuthState.refreshing;
    if (event.session != null &&
        (event.event == AuthChangeEvent.initialSession ||
            event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.tokenRefreshed ||
            event.event == AuthChangeEvent.userUpdated ||
            event.event == AuthChangeEvent.passwordRecovery)) {
      markAuthenticated(reason: event.event.name);
    } else if (event.event == AuthChangeEvent.signedOut &&
        (_explicitLogout ||
            _state == AppAuthState.definitivelyUnauthenticated)) {
      markDefinitelyUnauthenticated(reason: 'confirmed_signed_out');
    } else if (event.event == AuthChangeEvent.signedOut) {
      authDiagnostics.log('AUTH_SIGNED_OUT_DURING_REFRESH', {
        'refreshInProgress': AuthDiagnostics.yesNo(refreshInProgress),
      });
      _transition(AppAuthState.refreshing, reason: 'signed_out_pending_review');
    }
    _lastHasSession = event.session != null;
    _lastHasRefreshToken = event.session?.refreshToken?.isNotEmpty == true;
    authDiagnostics.logAuthEvent(
      event: event.event.name,
      stateBefore: stateBefore.name,
      hasSessionBefore: hasSessionBefore,
      hasRefreshTokenBefore: hasRefreshTokenBefore,
      stateAfter: _state.name,
      sessionAfter: event.session,
      explicitLogout: explicitLogout,
      refreshInProgress: refreshInProgress,
    );
  }

  void _transition(AppAuthState next, {required String reason}) {
    final previous = _state;
    if (previous == next) return;
    _state = next;
    authDiagnostics.logTransition(
      from: previous.name,
      to: next.name,
      reason: reason,
    );
    notifyListeners();
  }
}

final appAuthCoordinator = AppAuthCoordinator();
