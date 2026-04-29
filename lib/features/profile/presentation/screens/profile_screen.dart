import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../auth/data/auth_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _password = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _profile;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _repo.myProfile();
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _changePassword() async {
    setState(() => _loading = true);
    try {
      await _repo.updatePassword(_password.text);
      _password.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _repo.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);
    try {
      await _repo.deleteMyAccount();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete account error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '-';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(email, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Role: ${_profile?['role'] ?? '-'}'),
          Text('Gym: ${_profile?['gym_id'] ?? '-'}'),
          const SizedBox(height: 32),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'Change password',
            loading: _loading,
            onPressed: _changePassword,
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: _logout, child: const Text('Logout')),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _deleteAccount,
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}
