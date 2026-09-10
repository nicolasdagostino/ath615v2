import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_diagnostics.dart';

enum SessionAccessState {
  valid,
  accountInvalid,
  noGymAccess,
  gymAccessDisabled,
  transientFailure,
}

String? currentSessionAccessDestination;

void clearRecordedSessionAccess() => currentSessionAccessDestination = null;

void recordSessionAccessResult(SessionAccessResult result) {
  if (result.state == SessionAccessState.transientFailure) return;
  currentSessionAccessDestination = switch (result.state) {
    SessionAccessState.valid => null,
    _ => result.destination,
  };
}

bool shouldRevalidateAccessOnLifecycle(AppLifecycleState state) =>
    state == AppLifecycleState.resumed;

String? accessDestinationOnResume(SessionAccessResult result) {
  if (result.state == SessionAccessState.accountInvalid ||
      result.state == SessionAccessState.noGymAccess ||
      result.state == SessionAccessState.gymAccessDisabled ||
      result.destination == '/app') {
    return result.destination;
  }
  return null;
}

class SessionAccessResult {
  const SessionAccessResult(this.state, {this.destination});

  final SessionAccessState state;
  final String? destination;
}

abstract interface class SessionAccessDataSource {
  Future<void> validateAuthUser();
  Future<void> recoverAuthSession();
  Future<Map<String, dynamic>?> loadProfile(String userId);
  Future<List<Map<String, dynamic>>> loadGymRelations(String userId);
  Future<void> selectGym(String gymId);
  Future<void> clearLocalSession();
}

class SupabaseSessionAccessDataSource implements SessionAccessDataSource {
  SupabaseSessionAccessDataSource(this.client);

  final SupabaseClient client;

  @override
  Future<void> validateAuthUser() async {
    final session = client.auth.currentSession;
    authDiagnostics.logSessionSnapshot(
      'AUTH_REVALIDATE_START',
      session: session,
    );
    await client.auth.getUser();
    authDiagnostics.log('AUTH_GET_USER_SUCCESS', const {});
  }

  @override
  Future<void> recoverAuthSession() async {
    authDiagnostics.logRefresh(
      event: 'AUTH_REFRESH_START',
      origin: 'a615_revalidation',
      session: client.auth.currentSession,
    );
    await client.auth.refreshSession();
    await client.auth.getUser();
    authDiagnostics.logRefresh(
      event: 'AUTH_REFRESH_SUCCESS',
      origin: 'a615_revalidation',
      session: client.auth.currentSession,
    );
  }

  @override
  Future<Map<String, dynamic>?> loadProfile(String userId) async => client
      .from('profiles')
      .select('id, role, gym_id, is_active')
      .eq('id', userId)
      .maybeSingle();

  @override
  Future<List<Map<String, dynamic>>> loadGymRelations(String userId) async =>
      List<Map<String, dynamic>>.from(
            await client
                .from('gym_members')
                .select('gym_id, role, is_active, gyms(name, lifecycle_status)')
                .eq('user_id', userId),
          )
          .where((row) {
            final gym = row['gyms'];
            return gym is Map &&
                (gym['lifecycle_status'] ?? 'active') == 'active';
          })
          .toList(growable: false);

  @override
  Future<void> selectGym(String gymId) =>
      client.rpc('select_effective_gym', params: {'p_gym_id': gymId});

  @override
  Future<void> clearLocalSession() => Future<void>.sync(() {
    authDiagnostics.log('AUTH_SIGNOUT_UNRECOVERABLE', const {});
    return client.auth.signOut(scope: SignOutScope.local);
  });
}

bool isDefinitiveAuthInvalidation(Object error) {
  if (error is! AuthException) return false;
  final status = error.statusCode;
  if (status != '401' && status != '403') return false;
  final message = error.message.toLowerCase();
  return message.contains('user not found') ||
      message.contains('user from sub claim') ||
      message.contains('invalid jwt') ||
      message.contains('session not found') ||
      message.contains('refresh token not found');
}

bool isRecoverableAccessTokenExpiry(Object error) {
  if (error is! AuthException) return false;
  final message = error.message.toLowerCase();
  return error.statusCode == '401' &&
      (message.contains('jwt expired') ||
          message.contains('token has expired') ||
          message.contains('access token expired'));
}

bool isDefinitiveRefreshFailure(Object error) {
  if (error is AuthSessionMissingException) return true;
  if (error is! AuthException) return false;
  final status = error.statusCode;
  if (status != '400' && status != '401' && status != '403') return false;
  final message = error.message.toLowerCase();
  return message.contains('refresh token not found') ||
      message.contains('invalid refresh token') ||
      message.contains('refresh token has already been used') ||
      message.contains('auth session missing') ||
      message.contains('session not found');
}

void logSanitizedAuthFailure(String event, Object error) {
  authDiagnostics.logAuthFailure(event, error);
}

class SessionAccessRevalidator {
  SessionAccessRevalidator(this.source);

  final SessionAccessDataSource source;
  Future<SessionAccessResult>? _inFlight;

  Future<SessionAccessResult> validate({
    required String userId,
    required String? cachedGymId,
  }) => _inFlight ??= _validate(
    userId: userId,
    cachedGymId: cachedGymId,
  ).whenComplete(() => _inFlight = null);

  Future<SessionAccessResult> _validate({
    required String userId,
    required String? cachedGymId,
  }) async {
    try {
      await source.validateAuthUser();
    } catch (error) {
      if (isRecoverableAccessTokenExpiry(error)) {
        try {
          await source.recoverAuthSession();
        } catch (refreshError) {
          logSanitizedAuthFailure('AUTH_REFRESH_FAIL', refreshError);
          if (!isDefinitiveRefreshFailure(refreshError) &&
              !isDefinitiveAuthInvalidation(refreshError)) {
            authDiagnostics.log('AUTH_REFRESH_TRANSIENT_FAIL', const {});
            return const SessionAccessResult(
              SessionAccessState.transientFailure,
            );
          }
          authDiagnostics.log('AUTH_REFRESH_UNRECOVERABLE', const {});
          await source.clearLocalSession();
          return const SessionAccessResult(
            SessionAccessState.accountInvalid,
            destination: '/login',
          );
        }
      } else {
        if (!isDefinitiveAuthInvalidation(error)) {
          authDiagnostics.log('AUTH_REVALIDATE_TRANSIENT_FAIL', const {});
          return const SessionAccessResult(SessionAccessState.transientFailure);
        }
        authDiagnostics.log('AUTH_REVALIDATE_UNRECOVERABLE', const {});
        await source.clearLocalSession();
        return const SessionAccessResult(
          SessionAccessState.accountInvalid,
          destination: '/login',
        );
      }
    }

    try {
      final profile = await source.loadProfile(userId);
      if (profile == null) {
        return const SessionAccessResult(
          SessionAccessState.noGymAccess,
          destination: '/join-gym',
        );
      }
      if (profile['role'] == 'owner') {
        if (profile['is_active'] == false) {
          return const SessionAccessResult(
            SessionAccessState.noGymAccess,
            destination: '/join-gym',
          );
        }
        return const SessionAccessResult(
          SessionAccessState.valid,
          destination: '/owner',
        );
      }

      final relations = await source.loadGymRelations(userId);
      final activeRelations = relations
          .where((row) => row['is_active'] == true)
          .toList(growable: false);
      if (activeRelations.isEmpty) {
        final hasInactiveRelation = relations.any(
          (row) => row['is_active'] == false,
        );
        if (hasInactiveRelation) {
          return const SessionAccessResult(
            SessionAccessState.gymAccessDisabled,
            destination: '/gym-access-disabled',
          );
        }
        return const SessionAccessResult(
          SessionAccessState.noGymAccess,
          destination: '/join-gym',
        );
      }
      final profileGymId = profile['gym_id']?.toString();
      final currentGymId = cachedGymId ?? profileGymId;
      if (activeRelations.any(
        (row) => row['gym_id']?.toString() == currentGymId,
      )) {
        return const SessionAccessResult(SessionAccessState.valid);
      }
      final fallbackGymId = activeRelations.first['gym_id'].toString();
      await source.selectGym(fallbackGymId);
      return const SessionAccessResult(
        SessionAccessState.valid,
        destination: '/app',
      );
    } catch (error) {
      logSanitizedAuthFailure('AUTH_CONTEXT_FAIL', error);
      if (isDefinitiveAuthInvalidation(error)) {
        authDiagnostics.log('AUTH_CONTEXT_UNRECOVERABLE', const {});
        await source.clearLocalSession();
        return const SessionAccessResult(
          SessionAccessState.accountInvalid,
          destination: '/login',
        );
      }
      return const SessionAccessResult(SessionAccessState.transientFailure);
    }
  }
}
