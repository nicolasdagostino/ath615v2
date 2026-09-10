import 'dart:async';

import 'package:ath615v2/features/auth/data/session_access_revalidator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SessionAccessRevalidator', () {
    test('only foreground resume triggers access revalidation', () {
      expect(
        shouldRevalidateAccessOnLifecycle(AppLifecycleState.resumed),
        isTrue,
      );
      expect(
        shouldRevalidateAccessOnLifecycle(AppLifecycleState.paused),
        isFalse,
      );
      expect(
        shouldRevalidateAccessOnLifecycle(AppLifecycleState.inactive),
        isFalse,
      );
    });

    test('resume leaves valid Owner inspection in place', () {
      expect(
        accessDestinationOnResume(
          const SessionAccessResult(
            SessionAccessState.valid,
            destination: '/owner',
          ),
        ),
        isNull,
      );
      expect(
        accessDestinationOnResume(
          const SessionAccessResult(
            SessionAccessState.accountInvalid,
            destination: '/login',
          ),
        ),
        '/login',
      );
      expect(
        accessDestinationOnResume(
          const SessionAccessResult(
            SessionAccessState.gymAccessDisabled,
            destination: '/gym-access-disabled',
          ),
        ),
        '/gym-access-disabled',
      );
    });
    test('valid user with active selected gym remains inside', () async {
      final source = _FakeSource();
      final result = await _validate(source);
      expect(result.state, SessionAccessState.valid);
      expect(result.destination, isNull);
      expect(source.signOuts, 0);
    });

    for (final message in [
      'User from sub claim in JWT does not exist',
      'Invalid JWT',
      'Session not found',
    ]) {
      test(
        'definitive auth invalidation clears local session: $message',
        () async {
          final source = _FakeSource(
            authError: AuthException(message, statusCode: '403'),
          );
          final result = await _validate(source);
          expect(result.state, SessionAccessState.accountInvalid);
          expect(result.destination, '/login');
          expect(source.signOuts, 1);
        },
      );
    }

    test(
      'missing profile removes protected context without assuming network failure',
      () async {
        final result = await _validate(_FakeSource(profile: null));
        expect(result.state, SessionAccessState.noGymAccess);
        expect(result.destination, '/join-gym');
      },
    );

    test('removed gym membership loses gym context but keeps auth', () async {
      final source = _FakeSource(relations: const []);
      final result = await _validate(source);
      expect(result.state, SessionAccessState.noGymAccess);
      expect(source.signOuts, 0);
    });

    test('inactive gym membership loses gym context', () async {
      final source = _FakeSource(
        profile: {'role': 'athlete', 'gym_id': 'gym-1', 'is_active': false},
        relations: const [
          {'gym_id': 'gym-1', 'is_active': false},
        ],
      );
      final result = await _validate(source);
      expect(result.state, SessionAccessState.gymAccessDisabled);
      expect(result.destination, '/gym-access-disabled');
      expect(source.signOuts, 0);
    });

    test(
      'multiple inactive gym memberships remain explicitly disabled',
      () async {
        final result = await _validate(
          _FakeSource(
            relations: const [
              {'gym_id': 'gym-1', 'is_active': false},
              {'gym_id': 'gym-2', 'is_active': false},
            ],
          ),
        );
        expect(result.state, SessionAccessState.gymAccessDisabled);
        expect(result.destination, '/gym-access-disabled');
      },
    );

    test('inactive current gym falls back to a second active gym', () async {
      final source = _FakeSource(
        profile: {'role': 'athlete', 'gym_id': 'gym-1', 'is_active': false},
        relations: const [
          {'gym_id': 'gym-1', 'is_active': false},
          {'gym_id': 'gym-2', 'is_active': true},
        ],
      );
      final result = await _validate(source);
      expect(result.state, SessionAccessState.valid);
      expect(result.destination, '/app');
      expect(source.selectedGyms, ['gym-2']);
    });

    test('second active gym uses existing selector RPC', () async {
      final source = _FakeSource(
        relations: const [
          {'gym_id': 'gym-2', 'is_active': true},
        ],
      );
      final result = await _validate(source);
      expect(result.destination, '/app');
      expect(source.selectedGyms, ['gym-2']);
    });

    for (final error in <Object>[
      Exception('SocketException: offline'),
      TimeoutException('timeout'),
      const AuthException('server unavailable', statusCode: '500'),
    ]) {
      test('transient failure does not sign out: $error', () async {
        final source = _FakeSource(authError: error);
        final result = await _validate(source);
        expect(result.state, SessionAccessState.transientFailure);
        expect(source.signOuts, 0);
      });
    }

    test('expired access token recovers through the refresh session', () async {
      final source = _FakeSource(
        authError: const AuthException('JWT expired', statusCode: '401'),
      );
      final result = await _validate(source);
      expect(result.state, SessionAccessState.valid);
      expect(source.refreshes, 1);
      expect(source.signOuts, 0);
    });

    test('invalid refresh token clears the local session', () async {
      final source = _FakeSource(
        authError: const AuthException('JWT expired', statusCode: '401'),
        refreshError: const AuthException(
          'Refresh token not found',
          statusCode: '401',
        ),
      );
      final result = await _validate(source);
      expect(result.state, SessionAccessState.accountInvalid);
      expect(source.refreshes, 1);
      expect(source.signOuts, 1);
    });

    test('temporary refresh failure preserves the session', () async {
      final source = _FakeSource(
        authError: const AuthException('JWT expired', statusCode: '401'),
        refreshError: TimeoutException('refresh timeout'),
      );
      final result = await _validate(source);
      expect(result.state, SessionAccessState.transientFailure);
      expect(source.signOuts, 0);
    });

    test('owner remains in owner context without gym relation', () async {
      final result = await _validate(
        _FakeSource(
          profile: {'role': 'owner', 'gym_id': null, 'is_active': true},
        ),
      );
      expect(result.destination, '/owner');
    });

    test('concurrent invalidations share one validation and signout', () async {
      final source = _FakeSource(
        authError: const AuthException('Invalid JWT', statusCode: '401'),
      );
      final validator = SessionAccessRevalidator(source);
      final results = await Future.wait([
        validator.validate(userId: 'user', cachedGymId: 'gym-1'),
        validator.validate(userId: 'user', cachedGymId: 'gym-1'),
      ]);
      expect(results.map((r) => r.destination), everyElement('/login'));
      expect(source.authChecks, 1);
      expect(source.signOuts, 1);
    });

    test(
      'data-source failure after auth check remains non-destructive',
      () async {
        final source = _FakeSource(profileError: Exception('network'));
        final result = await _validate(source);
        expect(result.state, SessionAccessState.transientFailure);
        expect(source.signOuts, 0);
      },
    );
  });
}

Future<SessionAccessResult> _validate(_FakeSource source) =>
    SessionAccessRevalidator(
      source,
    ).validate(userId: 'user', cachedGymId: 'gym-1');

class _FakeSource implements SessionAccessDataSource {
  _FakeSource({
    this.authError,
    this.refreshError,
    this.profileError,
    Object? profile = _defaultProfile,
    this.relations = const [
      {'gym_id': 'gym-1', 'is_active': true},
    ],
  }) : profile = profile == null
           ? null
           : Map<String, dynamic>.from(profile as Map);

  static const _defaultProfile = {
    'role': 'athlete',
    'gym_id': 'gym-1',
    'is_active': true,
  };

  final Object? authError;
  final Object? refreshError;
  final Object? profileError;
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> relations;
  int authChecks = 0;
  int refreshes = 0;
  int signOuts = 0;
  final List<String> selectedGyms = [];

  @override
  Future<void> validateAuthUser() async {
    authChecks++;
    if (authError != null) throw authError!;
  }

  @override
  Future<void> recoverAuthSession() async {
    refreshes++;
    if (refreshError != null) throw refreshError!;
  }

  @override
  Future<Map<String, dynamic>?> loadProfile(String userId) async {
    if (profileError != null) throw profileError!;
    return profile;
  }

  @override
  Future<List<Map<String, dynamic>>> loadGymRelations(String userId) async =>
      relations;

  @override
  Future<void> selectGym(String gymId) async => selectedGyms.add(gymId);

  @override
  Future<void> clearLocalSession() async => signOuts++;
}
