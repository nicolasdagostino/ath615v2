import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../workouts/presentation/widgets/edit_workout_sheet.dart';
import '../../../workouts/presentation/widgets/workout_card.dart';
import '../../../workouts/presentation/widgets/workouts_empty_state.dart';
import '../../../workouts/presentation/widgets/workouts_loading_state.dart';
import '../widgets/explore_header.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

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
      ).showSnackBar(SnackBar(content: Text(appStrings.exploreLoadError(e))));
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await _load(showLoading: false);
  }

  Future<void> _deleteWorkout(String workoutId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(appStrings.deleteWorkoutTitle),
          content: Text(appStrings.deleteWorkoutMsg),
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
        SnackBar(content: Text(appStrings.exploreDeleteWorkoutError(e))),
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
    final filteredWorkouts = _filteredWorkouts;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Column(
          children: [
            ExploreHeader(
              unreadNotifications: widget.unreadNotifications,
              onOpenNotifications: widget.onOpenNotifications,
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: TextField(
                style: GoogleFonts.barlowCondensed(
                  color: const Color(0xFF384152),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: appStrings.exploreSearchWorkouts,
                  hintStyle: GoogleFonts.barlowCondensed(
                    color: const Color(0xFF8F96A3),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF8F96A3)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _programs.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final all = index == 0;
                  final program = all ? null : _programs[index - 1];
                  final id = program?['id']?.toString();
                  final selected = all
                      ? _selectedProgramId == null
                      : _selectedProgramId == id;

                  final label = all
                      ? appStrings.exploreAllPrograms
                      : program?['name']?.toString() ??
                            appStrings.workoutProgram;

                  return ChoiceChip(
                    selected: selected,
                    label: Text(
                      label.toUpperCase(),
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF8F96A3),
                        height: 1.0,
                      ),
                    ),
                    selectedColor: const Color(0xFFB59B6A),
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    onSelected: (_) {
                      setState(() => _selectedProgramId = all ? null : id);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFB59B6A),
                onRefresh: _refresh,
                child: _loading
                    ? const WorkoutsLoadingState()
                    : filteredWorkouts.isEmpty
                    ? const WorkoutsEmptyState()
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                        itemCount: filteredWorkouts.length,
                        itemBuilder: (context, index) {
                          final workout = filteredWorkouts[index];
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
