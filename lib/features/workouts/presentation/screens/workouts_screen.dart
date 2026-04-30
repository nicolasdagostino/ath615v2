import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/manage_programs_sheet.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  bool _loading = true;
  String? _role;
  String? _gymId;

  SupabaseClient get _client => Supabase.instance.client;

  bool get _canManage => _role == 'admin' || _role == 'owner';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);

    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final profile = await _client
          .from('profiles')
          .select('role, gym_id')
          .eq('id', user.id)
          .single();

      if (!mounted) return;
      setState(() {
        _role = profile['role'] as String?;
        _gymId = profile['gym_id'] as String?;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Workouts load error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPrograms() async {
    final gymId = _gymId;
    if (gymId == null) return;

    await showManageProgramsSheet(
      context: context,
      client: _client,
      gymId: gymId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workouts'),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: 'Programs',
              onPressed: _openPrograms,
              icon: const Icon(Icons.category_outlined),
            ),
          IconButton(onPressed: _loadProfile, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('No workouts yet.')),
    );
  }
}
