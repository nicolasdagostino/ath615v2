import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  Completer<AuthRefreshResolution>? _refreshResolution;
  Future<AuthRefreshResolution>? _sessionRefreshWork;

  AppAuthState get state => _state;
  bool get isTransitioning =>
      _state == AppAuthState.initializing || _state == AppAuthState.refreshing;
  bool get isSessionRefreshPending =>
      _state == AppAuthState.refreshing && _refreshResolution != null;

  void initializeFromSession(Session? session) {
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
    try {
      return await pending.future.timeout(timeout);
    } on TimeoutException {
      final latestSession = currentSession();
      if (latestSession != null && !latestSession.isExpired) {
        _completeRefresh(AuthRefreshResolution.refreshed);
        return AuthRefreshResolution.refreshed;
      }
      _completeRefresh(AuthRefreshResolution.transientFailure);
      return AuthRefreshResolution.transientFailure;
    }
  }

  Future<AuthRefreshResolution> resolveSessionRefresh({
    required Session? Function() currentSession,
    required Future<void> Function() refreshSession,
    required bool Function(Object error) isDefinitiveFailure,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _sessionRefreshWork ??= _resolveSessionRefresh(
      currentSession: currentSession,
      refreshSession: refreshSession,
      isDefinitiveFailure: isDefinitiveFailure,
      timeout: timeout,
    ).whenComplete(() => _sessionRefreshWork = null);
  }

  Future<AuthRefreshResolution> _resolveSessionRefresh({
    required Session? Function() currentSession,
    required Future<void> Function() refreshSession,
    required bool Function(Object error) isDefinitiveFailure,
    required Duration timeout,
  }) async {
    final session = currentSession();
    if (session != null && !session.isExpired) {
      _completeRefresh(AuthRefreshResolution.refreshed);
      return AuthRefreshResolution.refreshed;
    }

    try {
      await refreshSession().timeout(timeout);
    } on TimeoutException {
      _completeRefresh(AuthRefreshResolution.transientFailure);
      return AuthRefreshResolution.transientFailure;
    } catch (error) {
      final resolution = isDefinitiveFailure(error)
          ? AuthRefreshResolution.definitiveFailure
          : AuthRefreshResolution.transientFailure;
      _completeRefresh(resolution);
      return resolution;
    }

    if (_explicitLogout || _state == AppAuthState.definitivelyUnauthenticated) {
      return AuthRefreshResolution.definitiveFailure;
    }
    final refreshedSession = currentSession();
    final resolution = refreshedSession != null && !refreshedSession.isExpired
        ? AuthRefreshResolution.refreshed
        : AuthRefreshResolution.transientFailure;
    _completeRefresh(resolution);
    return resolution;
  }

  void markAuthenticated({String reason = 'auth_confirmed'}) {
    _explicitLogout = false;
    _completeRefresh(AuthRefreshResolution.refreshed);
    _transition(AppAuthState.authenticated, reason: reason);
  }

  void preserveAfterTransientFailure({required bool sessionPresent}) {
    if (sessionPresent) {
      markAuthenticated(reason: 'refresh_transient_session_preserved');
    }
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
    if (_explicitLogout) {
      if (event.event == AuthChangeEvent.signedOut) {
        markDefinitelyUnauthenticated(reason: 'confirmed_signed_out');
      }
      return;
    }
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
      _transition(AppAuthState.refreshing, reason: 'signed_out_pending_review');
    }
  }

  void _completeRefresh(AuthRefreshResolution resolution) {
    final pending = _refreshResolution;
    _refreshResolution = null;
    if (pending != null && !pending.isCompleted) pending.complete(resolution);
  }

  void _transition(AppAuthState next, {required String reason}) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }
}

final appAuthCoordinator = AppAuthCoordinator();
