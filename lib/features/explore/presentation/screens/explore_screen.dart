import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../workouts/presentation/widgets/edit_workout_sheet.dart';
import '../../../workouts/presentation/widgets/workout_card.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  bool _loading = true;
  String? _role;
  String? _gymId;
  List<Map<String, dynamic>> _workouts = [];

  SupabaseClient get _client => Supabase.instance.client;

  bool get _canManage => _role == 'admin' || _role == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final profile = await _client
          .from('profiles')
          .select('role, gym_id')
          .eq('id', user.id)
          .single();

      final gymId = profile['gym_id'] as String?;
      final today = DateTime.now().toIso8601String().split('T').first;

      final workouts = gymId == null
          ? <Map<String, dynamic>>[]
          : await _client
                .from('workouts')
                .select(
                  'id, workout_date, description, image_url, program_id, programs(name), workout_likes(user_id), workout_comments(id, body, user_id, created_at)',
                )
                .eq('gym_id', gymId)
                .lt('workout_date', today)
                .order('workout_date', ascending: false)
                .limit(60);

      if (!mounted) return;
      setState(() {
        _role = profile['role'] as String?;
        _gymId = gymId;
        _workouts = List<Map<String, dynamic>>.from(workouts);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Explore load error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteWorkout(String workoutId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete workout?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _client.from('workouts').delete().eq('id', workoutId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete workout error: $e')));
    }
  }

  Future<void> _editWorkout(Map<String, dynamic> workout) async {
    final gymId = _gymId;
    if (gymId == null) return;

    await showEditWorkoutSheet(
      context: context,
      client: _client,
      workoutId: workout['id'].toString(),
      gymId: gymId,
      currentProgramId: workout['program_id'].toString(),
      currentDescription: workout['description']?.toString() ?? '',
      currentDate: workout['workout_date'].toString(),
      currentImageUrl: workout['image_url']?.toString(),
      onUpdated: _load,
    );
  }

  String _formatDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workouts.isEmpty
          ? const Center(child: Text('No previous workouts yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _workouts.length,
              itemBuilder: (context, index) {
                final workout = _workouts[index];
                final program = workout['programs'] as Map<String, dynamic>?;

                final likes = List<Map<String, dynamic>>.from(
                  workout['workout_likes'] ?? [],
                );

                final comments = List<Map<String, dynamic>>.from(
                  workout['workout_comments'] ?? [],
                );

                return WorkoutCard(
                  workoutId: workout['id'].toString(),
                  program: program?['name']?.toString() ?? 'Workout',
                  description: workout['description']?.toString() ?? '',
                  date: _formatDate(workout['workout_date'].toString()),
                  imageUrl: workout['image_url']?.toString(),
                  likes: likes,
                  comments: comments,
                  canManage: _canManage,
                  onEdit: () => _editWorkout(workout),
                  onDelete: () => _deleteWorkout(workout['id'].toString()),
                );
              },
            ),
    );
  }
}
