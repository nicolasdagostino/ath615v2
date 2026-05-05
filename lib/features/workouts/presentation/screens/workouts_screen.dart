import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/create_workout_sheet.dart';
import '../widgets/edit_workout_sheet.dart';
import '../widgets/manage_programs_sheet.dart';
import '../widgets/workout_card.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
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

      final workouts = gymId == null
          ? <Map<String, dynamic>>[]
          : await _client
                .from('workouts')
                .select(
                  'id, workout_date, description, image_url, program_id, programs(name), workout_likes(user_id), workout_comments(id, body, user_id, created_at)',
                )
                .eq('gym_id', gymId)
                .eq(
                  'workout_date',
                  DateTime.now().toIso8601String().split('T').first,
                )
                .order('workout_date', ascending: false);

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
      ).showSnackBar(SnackBar(content: Text(appStrings.workoutsLoadError(e))));
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

  Future<void> _openCreateWorkout() async {
    final gymId = _gymId;
    if (gymId == null) return;

    await showCreateWorkoutSheet(
      context: context,
      client: _client,
      gymId: gymId,
      onCreated: _load,
    );
  }

  Future<void> _deleteWorkout(String workoutId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(appStrings.workoutsDeleteTitle),
          content: Text(appStrings.workoutsDeleteMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(appStrings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(appStrings.delete),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.workoutsDeleteError(e))),
      );
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
      floatingActionButton: _canManage
          ? FloatingActionButton(
              onPressed: _openCreateWorkout,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  appStrings.workoutsTitle,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (_canManage)
                  IconButton(
                    tooltip: appStrings.workoutsPrograms,
                    onPressed: _openPrograms,
                    icon: const Icon(Icons.category_outlined),
                  ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _workouts.isEmpty
                ? Center(child: Text(appStrings.workoutsNoToday))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _workouts.length,
                    itemBuilder: (context, index) {
                      final workout = _workouts[index];
                      final program =
                          workout['programs'] as Map<String, dynamic>?;

                      final likes = List<Map<String, dynamic>>.from(
                        workout['workout_likes'] ?? [],
                      );

                      final comments =
                          List<Map<String, dynamic>>.from(
                            workout['workout_comments'] ?? [],
                          )..sort(
                            (a, b) => (b['created_at'] ?? '')
                                .toString()
                                .compareTo((a['created_at'] ?? '').toString()),
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
                        onDelete: () =>
                            _deleteWorkout(workout['id'].toString()),
                        onChanged: _load,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
