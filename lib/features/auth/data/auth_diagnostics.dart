import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AuthDiagnosticSink = void Function(String message);

class AuthDiagnostics {
  AuthDiagnostics({AuthDiagnosticSink? sink}) : _sink = sink ?? _releaseLogSink;

  final AuthDiagnosticSink _sink;
  int _resumeCycleId = 0;
  String? _persistSessionKey;
  bool? _persistedSessionPresent;

  int get resumeCycleId => _resumeCycleId;
  bool? get persistedSessionPresent => _persistedSessionPresent;

  Future<void> initialize({
    required String supabaseUrl,
    required Session? session,
    required String coordinatorState,
  }) async {
    final projectRef = Uri.parse(supabaseUrl).host.split('.').first;
    _persistSessionKey = 'sb-$projectRef-auth-token';
    await refreshPersistedSessionPresence();
    logSessionSnapshot(
      'AUTH_STARTUP_SNAPSHOT',
      session: session,
      coordinatorState: coordinatorState,
    );
  }

  int logLifecycle({
    required String lifecycleState,
    required Session? session,
    required String coordinatorState,
  }) {
    if (lifecycleState == 'resumed') _resumeCycleId++;
    logSessionSnapshot(
      'AUTH_LIFECYCLE',
      session: session,
      coordinatorState: coordinatorState,
      extra: {'lifecycle': lifecycleState},
    );
    return _resumeCycleId;
  }

  void logRefresh({
    required String event,
    required String origin,
    required Session? session,
    String? phase,
  }) {
    logSessionSnapshot(
      event,
      session: session,
      extra: {'origin': origin, 'phase': ?phase},
    );
  }

  void logAuthEvent({
    required String event,
    required String stateBefore,
    required bool hasSessionBefore,
    required bool hasRefreshTokenBefore,
    required String stateAfter,
    required Session? sessionAfter,
    required bool explicitLogout,
    required bool refreshInProgress,
  }) {
    log('AUTH_EVENT', {
      'event': event,
      'stateBefore': stateBefore,
      'hasSessionBefore': yesNo(hasSessionBefore),
      'hasRefreshTokenBefore': yesNo(hasRefreshTokenBefore),
      'stateAfter': stateAfter,
      'hasSessionAfter': yesNo(sessionAfter != null),
      'hasRefreshTokenAfter': yesNo(
        sessionAfter?.refreshToken?.isNotEmpty == true,
      ),
      'explicitLogout': yesNo(explicitLogout),
      'refreshInProgress': yesNo(refreshInProgress),
    });
    unawaited(
      refreshPersistedSessionPresence(event: 'AUTH_STORAGE_AFTER_EVENT'),
    );
  }

  void logTransition({
    required String from,
    required String to,
    required String reason,
  }) {
    log('AUTH_STATE', {'from': from, 'to': to, 'reason': reason});
  }

  void logRouter({
    required String event,
    required String reason,
    required String state,
    required bool hasSession,
  }) {
    log(event, {
      'reason': reason,
      'state': state,
      'hasSession': yesNo(hasSession),
      'persistedSessionPresent': yesNoNullable(_persistedSessionPresent),
    });
  }

  void logAuthFailure(String event, Object error) {
    String? status;
    String? code;
    if (error is AuthException) {
      status = error.statusCode;
      code = error.code;
    }
    log(event, {
      'exception': error.runtimeType.toString(),
      'status': status ?? 'none',
      'code': code ?? 'none',
      'category': authFailureCategory(error),
      'message': sanitizedAuthMessage(error),
    });
  }

  void logSessionSnapshot(
    String event, {
    required Session? session,
    String? coordinatorState,
    Map<String, Object?> extra = const {},
  }) {
    final now = DateTime.now().toUtc();
    final expiresAt = session?.expiresAt;
    final nowEpoch = now.millisecondsSinceEpoch ~/ 1000;
    final secondsToExpiry = expiresAt == null ? null : expiresAt - nowEpoch;
    log(event, {
      'state': ?coordinatorState,
      'hasSession': yesNo(session != null),
      'hasRefreshToken': yesNo(session?.refreshToken?.isNotEmpty == true),
      'expiresAt': expiresAt ?? 'none',
      'now': nowEpoch,
      'secondsToExpiry': secondsToExpiry ?? 'none',
      'isExpired': yesNo(secondsToExpiry != null && secondsToExpiry <= 0),
      'persistedSessionPresent': yesNoNullable(_persistedSessionPresent),
      ...extra,
    }, timestamp: now);
  }

  Future<void> refreshPersistedSessionPresence({String? event}) async {
    final key = _persistSessionKey;
    if (key == null) return;
    if (event != null) await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    _persistedSessionPresent = prefs.containsKey(key);
    if (event != null) {
      log(event, {'persistedSessionPresent': yesNo(_persistedSessionPresent!)});
    }
  }

  void log(String event, Map<String, Object?> fields, {DateTime? timestamp}) {
    final time = (timestamp ?? DateTime.now().toUtc()).toIso8601String();
    final values = fields.entries.map((entry) => '${entry.key}=${entry.value}');
    _sink('$time $event resumeCycleId=$_resumeCycleId ${values.join(' ')}');
  }

  static String yesNo(bool value) => value ? 'YES' : 'NO';
  static String yesNoNullable(bool? value) =>
      value == null ? 'UNKNOWN' : yesNo(value);

  static String authFailureCategory(Object error) {
    if (error is AuthRetryableFetchException) {
      final status = int.tryParse(error.statusCode ?? '');
      return status != null && status >= 500
          ? 'server_retryable'
          : 'network_retryable';
    }
    if (error is AuthSessionMissingException) return 'session_missing';
    if (error is AuthException) {
      final code = error.code?.toLowerCase() ?? '';
      final message = error.message.toLowerCase();
      if (code.contains('refresh_token_already_used') ||
          message.contains('already been used')) {
        return 'refresh_token_already_used';
      }
      if (code.contains('refresh_token_not_found') ||
          message.contains('refresh token not found')) {
        return 'refresh_token_not_found';
      }
      if (code.contains('invalid_grant') || message.contains('invalid grant')) {
        return 'invalid_grant';
      }
      if (message.contains('invalid refresh token')) {
        return 'invalid_refresh_token';
      }
      if (error.statusCode == '401') return 'unauthorized';
      if (error.statusCode == '403') return 'forbidden';
      if (error is AuthUnknownException) {
        return 'malformed_response';
      }
      return 'unknown_auth_error';
    }
    return 'unknown_auth_error';
  }

  static String sanitizedAuthMessage(Object error) {
    final category = authFailureCategory(error);
    return switch (category) {
      'network_retryable' => 'network_error',
      'server_retryable' => 'server_error',
      'malformed_response' => 'malformed_auth_response',
      'unknown_auth_error' => 'auth_error',
      _ => category,
    };
  }

  static void _releaseLogSink(String message) {
    debugPrint('A615_AUTH $message');
  }
}

final authDiagnostics = AuthDiagnostics();
