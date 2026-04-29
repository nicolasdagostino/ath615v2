import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';
import '../../data/auth_repository.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  bool _loading = false;
  bool _sessionReady = false;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _waitForSession();
  }

  Future<void> _waitForSession() async {
    for (var i = 0; i < 20; i++) {
      if (Supabase.instance.client.auth.currentSession != null) {
        if (mounted) setState(() => _sessionReady = true);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (mounted) setState(() => _sessionReady = false);
  }

  Future<void> _submit() async {
    if (!_sessionReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session not ready. Please open the email link again.'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _repo.updatePassword(_password.text);
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Password update error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set new password')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _sessionReady
                ? 'Create your new password.'
                : 'Opening secure invitation...',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: _sessionReady ? 'Save password' : 'Waiting for session...',
            loading: _loading,
            onPressed: _sessionReady ? _submit : null,
          ),
        ],
      ),
    );
  }
}
