import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';

class OwnerScreen extends StatefulWidget {
  const OwnerScreen({super.key});

  @override
  State<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<OwnerScreen> {
  final _gymName = TextEditingController();
  final _email = TextEditingController();

  bool _creatingGym = false;
  bool _invitingAdmin = false;
  String? _gymId;

  final client = Supabase.instance.client;

  Future<void> _createGym() async {
    setState(() => _creatingGym = true);
    try {
      final res = await client.rpc(
        'create_gym',
        params: {'gym_name': _gymName.text.trim()},
      );
      if (!mounted) return;
      setState(() => _gymId = res as String);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create gym error: $e')));
    } finally {
      if (mounted) setState(() => _creatingGym = false);
    }
  }

  Future<void> _inviteAdmin() async {
    if (_gymId == null) return;

    setState(() => _invitingAdmin = true);
    try {
      await client.functions.invoke(
        'owner-invite-admin',
        body: {'email': _email.text.trim(), 'gym_id': _gymId},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite error: $e')));
    } finally {
      if (mounted) setState(() => _invitingAdmin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset),
            onPressed: () => context.go('/reset-password'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await client.auth.signOut();
              if (!context.mounted) return;
              context.go('/login');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Create Gym'),
          const SizedBox(height: 12),
          TextField(
            controller: _gymName,
            decoration: const InputDecoration(labelText: 'Gym name'),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Create gym',
            loading: _creatingGym,
            onPressed: _createGym,
          ),
          const SizedBox(height: 32),
          const Text('Invite Admin'),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Admin email'),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Invite admin',
            loading: _invitingAdmin,
            onPressed: _inviteAdmin,
          ),
        ],
      ),
    );
  }
}
