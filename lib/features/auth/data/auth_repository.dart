import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'athletelab://reset-password',
    );
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
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
    await signOut();
  }
}
