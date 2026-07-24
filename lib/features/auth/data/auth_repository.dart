import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  static bool _isSigningOut = false;

  static bool get isSigningOut => _isSigningOut;

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'full_name': fullName.trim(), 'role': 'athlete'},
    );
  }

  Future<void> resetPassword(String email) async {
    final normalizedEmail = email.trim().toLowerCase();

    await _client.auth.resetPasswordForEmail(
      normalizedEmail,
      redirectTo: 'athletelab://reset-password',
    );
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> _removeCurrentDeviceToken() async {
    final user = currentUser;
    if (user == null) return;

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      debugPrint('PUSH LOGOUT WARNING => could not obtain device token');
      return;
    }

    final normalizedToken = token?.trim();
    if (normalizedToken == null || normalizedToken.isEmpty) {
      debugPrint('PUSH LOGOUT WARNING => device token unavailable');
      return;
    }

    try {
      await _client
          .from('device_tokens')
          .delete()
          .eq('user_id', user.id)
          .eq('token', normalizedToken);
    } catch (_) {
      debugPrint('PUSH LOGOUT WARNING => could not remove device association');
    }
  }

  Future<void> signOut() async {
    _isSigningOut = true;
    try {
      await _removeCurrentDeviceToken();
      await _client.auth.signOut();
    } finally {
      _isSigningOut = false;
    }
  }

  Future<Map<String, dynamic>?> myProfile() async {
    final user = currentUser;
    if (user == null) return null;

    return _client
        .from('profiles')
        .select(
          'id, full_name, role, gym_id, email, phone, birth_date, avatar_url',
        )
        .eq('id', user.id)
        .maybeSingle();
  }

  Future<String?> myRole() async {
    final profile = await myProfile();
    return profile?['role'] as String?;
  }

  Future<void> deleteMyAccount() async {
    await _client.functions.invoke('delete-my-account');
    await _client.auth.signOut();
  }
}
