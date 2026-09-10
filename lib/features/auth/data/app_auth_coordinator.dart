import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_diagnostics.dart';

enum AppAuthState {
  initializing,
  refreshing,
  authenticated,
  definitivelyUnauthenticated,
}

enum AuthRefreshResolution { refreshed, transientFailure, definitiveFailure }

class AppAuthCoordinator extends ChangeNotifier {
  AppAuthState _state = AppAuthState.initializing;
  bool _explicitLogout = false;
  bool _lastHasSession = false;
  bool _lastHasRefreshToken = false;
  Completer<AuthRefreshResolution>? _refreshResolution;
  bool _signedOutDuringRefresh = false;

  AppAuthState get state => _state;
  bool get hasKnownSession => _lastHasSession;
  bool get isTransitioning =>
      _state == AppAuthState.initializing || _state == AppAuthState.refreshing;
  bool get isSessionRefreshPending =>
      _state == AppAuthState.refreshing && _refreshResolution != null;

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

  void beginRefresh({bool expectsSessionRefresh = false}) {
    if (_state == AppAuthState.definitivelyUnauthenticated) return;
    if (expectsSessionRefresh && _refreshResolution == null) {
      _signedOutDuringRefresh = false;
      _refreshResolution = Completer<AuthRefreshResolution>();
    }
    _transition(AppAuthState.refreshing, reason: 'revalidation');
  }

  Future<AuthRefreshResolution> waitForSessionRefresh({
    required Session? Function() currentSession,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final session = currentSession();
    if (session != null && !session.isExpired) {
      _completeRefresh(AuthRefreshResolution.refreshed);
      return AuthRefreshResolution.refreshed;
    }
    final pending = _refreshResolution;
    if (pending == null) return AuthRefreshResolution.transientFailure;
    authDiagnostics.log('AUTH_REFRESH_WAIT', const {});
    try {
      return await pending.future.timeout(timeout);
    } on TimeoutException {
      final latestSession = currentSession();
      if (latestSession != null && !latestSession.isExpired) {
        _completeRefresh(AuthRefreshResolution.refreshed);
        return AuthRefreshResolution.refreshed;
      }
      final resolution = _signedOutDuringRefresh && latestSession == null
          ? AuthRefreshResolution.definitiveFailure
          : AuthRefreshResolution.transientFailure;
      _completeRefresh(resolution);
      return resolution;
    }
  }

  void markAuthenticated({String reason = 'auth_confirmed'}) {
    _explicitLogout = false;
    _completeRefresh(AuthRefreshResolution.refreshed);
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
    _completeRefresh(AuthRefreshResolution.definitiveFailure);
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
      _signedOutDuringRefresh = true;
      authDiagnostics.log('AUTH_REFRESH_WAIT', {
        'reason': 'signed_out_pending_refresh_resolution',
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

  void _completeRefresh(AuthRefreshResolution resolution) {
    final pending = _refreshResolution;
    _refreshResolution = null;
    _signedOutDuringRefresh = false;
    if (pending != null && !pending.isCompleted) pending.complete(resolution);
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
