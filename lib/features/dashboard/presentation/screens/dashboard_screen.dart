import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _email = TextEditingController();
  bool _loading = false;

  Future<void> _inviteAthlete() async {
    setState(() => _loading = true);

    try {
      await Supabase.instance.client.functions.invoke(
        'admin-invite-athlete',
        body: {'email': _email.text.trim()},
      );

      if (!mounted) return;

      _email.clear();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Athlete invitation sent')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite athlete error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Invite athlete',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text('Send an invitation email to a new athlete.'),
          const SizedBox(height: 20),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Athlete email'),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Invite athlete',
            loading: _loading,
            onPressed: _inviteAthlete,
          ),
        ],
      ),
    );
  }
}
