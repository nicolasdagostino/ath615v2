import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_auth_coordinator.dart';
import 'password_policy.dart';
import 'session_access_revalidator.dart';

bool isPasswordRecoveryCallback(Uri uri) =>
    uri.scheme.toLowerCase() == 'athletelab' &&
    uri.host.toLowerCase() == 'reset-password';

enum RecoveryPhase { idle, exchanging, required, invalid }

enum PasswordReplacementResult {
  success,
  invalidPassword,
  mismatch,
  unavailable,
  failed,
}

abstract interface class RecoveryDataSource {
  bool get hasSession;
  Future<void> exchange(Uri uri);
  Future<void> validateUser();
  Future<void> updatePassword(String password);
  Future<void> signOutLocally();
}

class SupabaseRecoveryDataSource implements RecoveryDataSource {
  SupabaseRecoveryDataSource(this.client);
  final SupabaseClient client;
  @override
  bool get hasSession => client.auth.currentSession != null;

  @override
  Future<void> exchange(Uri uri) async {
    final params = {
      ...uri.queryParameters,
      ...Uri.splitQueryString(uri.fragment),
    };
    if (params.containsKey('error') ||
        params.containsKey('error_code') ||
        params.containsKey('error_description')) {
      throw const FormatException('Invalid recovery callback');
    }
    final code = params['code'];
    if (code != null && code.isNotEmpty) {
      // The SDK owns the verifier and checks its stored recovery intent.
      final result = await client.auth.exchangeCodeForSession(code);
      if (result.redirectType != AuthChangeEvent.passwordRecovery.name) {
        throw const FormatException('Missing recovery context');
      }
    } else if ((params['type'] == 'recovery' || params['type'] == 'invite') &&
        (params['refresh_token']?.isNotEmpty ?? false) &&
        (params['access_token']?.isNotEmpty ?? false)) {
      // Legacy recovery/invitation emails. setSession alone emits signedIn.
      await client.auth.setSession(
        params['refresh_token']!,
        accessToken: params['access_token'],
      );
    } else {
      throw const FormatException('Missing recovery context');
    }
    await validateUser();
  }

  @override
  Future<void> validateUser() async {
    if ((await client.auth.getUser()).user == null) {
      throw const AuthException('User not found', statusCode: '403');
    }
  }

  @override
  Future<void> updatePassword(String password) async {
    final result = await client.auth.updateUser(
      UserAttributes(password: password),
    );
    if (result.user == null) {
      throw const AuthException('User not found', statusCode: '403');
    }
  }

  @override
  Future<void> signOutLocally() =>
      client.auth.signOut(scope: SignOutScope.local);
}

// Only these non-sensitive values are persisted: pending, required, or no value.
// No callback, user identifier, password, code, verifier or token is stored here.
class PasswordRecoveryController extends ChangeNotifier {
  PasswordRecoveryController({
    required this.coordinator,
    required this.source,
    required this.readMarker,
    required this.writeMarker,
  });

  final AppAuthCoordinator coordinator;
  final RecoveryDataSource source;
  final Future<String?> Function() readMarker;
  final Future<void> Function(String?) writeMarker;
  RecoveryPhase phase = RecoveryPhase.idle;
  bool submitting = false;
  int _generation = 0;
  Future<void>? _callbackWork;
  Future<void> _storageWork = Future.value();
  bool get ready =>
      phase == RecoveryPhase.required &&
      coordinator.requiresPasswordRecovery &&
      source.hasSession;

  Future<void> _persist(String? marker) {
    final work = _storageWork.then((_) => writeMarker(marker));
    _storageWork = work.catchError((Object _) {});
    return work;
  }

  Future<void> initialize({Uri? initialUri}) async {
    final marker = await readMarker();
    if (initialUri != null && isPasswordRecoveryCallback(initialUri)) {
      await prepareCallback();
    } else if (marker == 'required' && source.hasSession) {
      coordinator.requirePasswordRecovery();
      phase = RecoveryPhase.required;
      await revalidate();
    } else if (marker != null) {
      coordinator.requirePasswordRecovery();
      await _invalidate();
    }
  }

  Future<void> prepareCallback() async {
    coordinator.requirePasswordRecovery();
    phase = RecoveryPhase.exchanging;
    notifyListeners();
    await _persist(
      'pending',
    ); // Must finish before the SDK establishes a session.
  }

  Future<void> handleCallback(Uri uri) {
    if (!isPasswordRecoveryCallback(uri)) return Future.value();
    if (_callbackWork != null) return _callbackWork!;
    if (ready || submitting) {
      return Future.value(); // Duplicate platform delivery.
    }
    return _callbackWork = _exchange(
      uri,
    ).whenComplete(() => _callbackWork = null);
  }

  Future<void> _exchange(Uri uri) async {
    final generation = ++_generation;
    try {
      await prepareCallback();
      await source.exchange(uri);
      if (generation != _generation) return;
      if (!source.hasSession) {
        throw const FormatException('Missing recovery session');
      }
      await _persist('required');
      if (generation != _generation) return;
      phase = RecoveryPhase.required;
      notifyListeners();
    } catch (_) {
      if (generation == _generation) await _invalidate();
    }
  }

  void observeAuthEvent(AuthState event) {
    coordinator.observeAuthEvent(event);
    if (coordinator.requiresPasswordRecovery &&
        phase == RecoveryPhase.required) {
      // Rebuild the form if the SDK temporarily removes/replaces its session.
      // A refresh event must never complete recovery, but it can restore readiness.
      notifyListeners();
    }
    if (event.event != AuthChangeEvent.passwordRecovery ||
        event.session == null ||
        !coordinator.requiresPasswordRecovery ||
        phase == RecoveryPhase.exchanging ||
        ready) {
      return;
    }
    phase = RecoveryPhase.exchanging;
    final generation = _generation;
    _persist('required')
        .then((_) {
          if (generation != _generation ||
              !coordinator.requiresPasswordRecovery) {
            return;
          }
          phase = RecoveryPhase.required;
          notifyListeners();
        })
        .catchError((Object _) async {
          await _invalidate();
        });
  }

  Future<void> revalidate() async {
    if (!ready) return;
    final generation = _generation;
    try {
      await source.validateUser();
    } catch (error) {
      if (generation == _generation &&
          (isDefinitiveAuthInvalidation(error) ||
              isDefinitiveRefreshFailure(error))) {
        await _invalidate();
      }
      // Transient validation failure cannot turn recovery into normal login.
    }
  }

  Future<PasswordReplacementResult> submit(
    String password,
    String confirmation,
  ) async {
    if (submitting || !ready) return PasswordReplacementResult.unavailable;
    if (!meetsPasswordPolicy(password)) {
      return PasswordReplacementResult.invalidPassword;
    }
    if (password != confirmation) return PasswordReplacementResult.mismatch;
    submitting = true;
    final generation = _generation;
    notifyListeners();
    try {
      await source.updatePassword(password);
      if (generation != _generation || !coordinator.requiresPasswordRecovery) {
        return PasswordReplacementResult.unavailable;
      }
      await _persist(null);
      if (generation != _generation) {
        return PasswordReplacementResult.unavailable;
      }
      phase = RecoveryPhase.idle;
      clearRecordedSessionAccess();
      coordinator.completePasswordRecovery();
      return PasswordReplacementResult.success;
    } catch (error) {
      if (generation == _generation &&
          (isDefinitiveAuthInvalidation(error) ||
              isDefinitiveRefreshFailure(error))) {
        await _invalidate();
      }
      return PasswordReplacementResult.failed;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> _invalidate() async {
    // Invalidation must beat any password update that is already in flight.
    _generation++;
    phase = RecoveryPhase.invalid;
    notifyListeners();
    // A pre-existing session must never rescue a failed recovery callback.
    // If local cleanup fails, retain the routing lock and allow retrying logout.
    try {
      await source.signOutLocally();
      await _persist(null);
      coordinator.beginExplicitLogout(reason: 'invalid_recovery');
    } catch (_) {
      coordinator.requirePasswordRecovery();
    }
    notifyListeners();
  }

  Future<bool> cancel() async {
    _generation++;
    await _callbackWork;
    await _invalidate();
    return !coordinator.requiresPasswordRecovery;
  }

  Future<void> clearAfterExplicitLogout() async {
    _generation++;
    final pendingCallback = _callbackWork;
    if (pendingCallback != null) {
      await pendingCallback;
      // The SDK may have installed a session after logout began.
      await source.signOutLocally();
    }
    phase = RecoveryPhase.idle;
    await _persist(null);
    notifyListeners();
  }
}

late PasswordRecoveryController passwordRecoveryController;
bool passwordRecoveryInitialized = false;

Future<void> initializePasswordRecovery(
  SupabaseClient client, {
  Uri? initialUri,
}) async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'a615_password_recovery_state';
  passwordRecoveryController = PasswordRecoveryController(
    coordinator: appAuthCoordinator,
    source: SupabaseRecoveryDataSource(client),
    readMarker: () async => prefs.getString(key),
    writeMarker: (value) async {
      final saved = value == null
          ? await prefs.remove(key)
          : await prefs.setString(key, value);
      if (!saved) throw StateError('Recovery state could not be saved');
    },
  );
  passwordRecoveryInitialized = true;
  await passwordRecoveryController.initialize(initialUri: initialUri);
}
