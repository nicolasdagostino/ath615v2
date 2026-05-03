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
  String _search = '';
  String? _selectedProgramId;

  List<Map<String, dynamic>> _workouts = [];
  List<Map<String, dynamic>> _programs = [];

  SupabaseClient get _client => Supabase.instance.client;

  bool get _canManage => _role == 'admin' || _role == 'owner';

  List<Map<String, dynamic>> get _filteredWorkouts {
    final query = _search.trim().toLowerCase();

    return _workouts.where((workout) {
      final description =
          workout['description']?.toString().toLowerCase() ?? '';
      final programName =
          (workout['programs'] as Map<String, dynamic>?)?['name']
              ?.toString()
              .toLowerCase() ??
          '';
      final programId = workout['program_id']?.toString();

      final matchesSearch =
          query.isEmpty ||
          description.contains(query) ||
          programName.contains(query);

      final matchesProgram =
          _selectedProgramId == null || programId == _selectedProgramId;

      return matchesSearch && matchesProgram;
    }).toList();
  }

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

      final programs = gymId == null
          ? <Map<String, dynamic>>[]
          : await _client
                .from('programs')
                .select('id, name')
                .eq('gym_id', gymId)
                .eq('is_active', true)
                .order('name');

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
        _programs = List<Map<String, dynamic>>.from(programs);
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
    final filteredWorkouts = _filteredWorkouts;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Text(
                  'Explore',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search workouts...',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) => setState(() => _search = value),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: DropdownButtonFormField<String?>(
                          initialValue: _selectedProgramId,
                          decoration: const InputDecoration(
                            labelText: 'Program',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All programs'),
                            ),
                            ..._programs.map(
                              (program) => DropdownMenuItem<String?>(
                                value: program['id'].toString(),
                                child: Text(
                                  program['name']?.toString() ?? 'Program',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedProgramId = value);
                          },
                        ),
                      ),
                      Expanded(
                        child: filteredWorkouts.isEmpty
                            ? const Center(child: Text('No workouts found.'))
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: filteredWorkouts.length,
                                itemBuilder: (context, index) {
                                  final workout = filteredWorkouts[index];
                                  final program =
                                      workout['programs']
                                          as Map<String, dynamic>?;

                                  final likes = List<Map<String, dynamic>>.from(
                                    workout['workout_likes'] ?? [],
                                  );

                                  final comments =
                                      List<Map<String, dynamic>>.from(
                                        workout['workout_comments'] ?? [],
                                      )..sort(
                                        (a, b) => (b['created_at'] ?? '')
                                            .toString()
                                            .compareTo(
                                              (a['created_at'] ?? '')
                                                  .toString(),
                                            ),
                                      );

                                  return WorkoutCard(
                                    workoutId: workout['id'].toString(),
                                    program:
                                        program?['name']?.toString() ??
                                        'Workout',
                                    description:
                                        workout['description']?.toString() ??
                                        '',
                                    date: _formatDate(
                                      workout['workout_date'].toString(),
                                    ),
                                    imageUrl: workout['image_url']?.toString(),
                                    likes: likes,
                                    comments: comments,
                                    canManage: _canManage,
                                    onEdit: () => _editWorkout(workout),
                                    onDelete: () => _deleteWorkout(
                                      workout['id'].toString(),
                                    ),
                                    onChanged: _load,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
