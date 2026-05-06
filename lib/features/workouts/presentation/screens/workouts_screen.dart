import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/create_workout_sheet.dart';
import '../widgets/edit_workout_sheet.dart';
import '../widgets/manage_programs_sheet.dart';
import '../widgets/workout_card.dart';
import '../widgets/workouts_header.dart';
import '../widgets/workouts_loading_state.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({
    super.key,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

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

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }

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
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await _load(showLoading: false);
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
              heroTag: 'create-workout',
              backgroundColor: const Color(0xFFB59B6A),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              onPressed: _openCreateWorkout,
              child: const Icon(Icons.add),
            )
          : null,
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Column(
          children: [
            WorkoutsHeader(
              canManage: _canManage,
              onPrograms: _openPrograms,
              unreadNotifications: widget.unreadNotifications,
              onOpenNotifications: widget.onOpenNotifications,
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFB59B6A),
                onRefresh: _refresh,
                child: _loading
                    ? const WorkoutsLoadingState()
                    : _workouts.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(28, 155, 28, 24),
                        children: const [
                          _RestDayEmptyState(),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
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
                                    .compareTo(
                                      (a['created_at'] ?? '').toString(),
                                    ),
                              );

                          return TweenAnimationBuilder<double>(
                            key: ValueKey(workout['id'].toString()),
                            tween: Tween(begin: 0, end: 1),
                            duration: Duration(
                              milliseconds: 220 + (index * 35).clamp(0, 220),
                            ),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 18 * (1 - value)),
                                  child: child,
                                ),
                              );
                            },
                            child: WorkoutCard(
                              workoutId: workout['id'].toString(),
                              program:
                                  program?['name']?.toString() ?? 'Workout',
                              description:
                                  workout['description']?.toString() ?? '',
                              date: _formatDate(
                                workout['workout_date'].toString(),
                              ),
                              imageUrl: workout['image_url']?.toString(),
                              likes: likes,
                              comments: comments,
                              canManage: _canManage,
                              onEdit: () => _editWorkout(workout),
                              onDelete: () =>
                                  _deleteWorkout(workout['id'].toString()),
                              onChanged: _load,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestDayEmptyState extends StatelessWidget {
  const _RestDayEmptyState();

  TextStyle _font(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = const Color(0xFF111318),
    double letterSpacing = 0,
    double height = 1.0,
  }) {
    return GoogleFonts.barlowCondensed(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'REST DAY',
          textAlign: TextAlign.center,
          style: _font(
            30,
            weight: FontWeight.w800,
            color: const Color(0xFF0E0E11),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          "Resting is as important as work. Let your mind and body rest, do some mobility and stretching. Don't be tempted to train if you feel good.",
          textAlign: TextAlign.center,
          style: _font(
            12,
            weight: FontWeight.w500,
            color: const Color(0xFF8F96A3),
            height: 1.35,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

