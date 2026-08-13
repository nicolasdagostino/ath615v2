import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutViewerContext {
  const WorkoutViewerContext({
    required this.role,
    required this.gymId,
    required this.isAccountActive,
  });

  final String? role;
  final String? gymId;
  final bool isAccountActive;
}

abstract interface class WorkoutsDateDataSource {
  Future<WorkoutViewerContext> loadViewer();

  Future<List<Map<String, dynamic>>> loadForDate({
    required String gymId,
    required DateTime date,
  });
}

class SupabaseWorkoutsDateDataSource implements WorkoutsDateDataSource {
  SupabaseWorkoutsDateDataSource(this.client);

  final SupabaseClient client;

  @override
  Future<WorkoutViewerContext> loadViewer() async {
    final user = client.auth.currentUser;
    if (user == null) {
      return const WorkoutViewerContext(
        role: null,
        gymId: null,
        isAccountActive: false,
      );
    }
    final profile = await client
        .from('profiles')
        .select('role, gym_id, is_active')
        .eq('id', user.id)
        .single();
    return WorkoutViewerContext(
      role: profile['role'] as String?,
      gymId: profile['gym_id'] as String?,
      isAccountActive: profile['is_active'] == true,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> loadForDate({
    required String gymId,
    required DateTime date,
  }) async {
    final value =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final rows = await client
        .from('workouts')
        .select(
          'id, workout_date, description, image_url, program_id, programs(name), workout_likes(user_id), workout_comments(id, body, user_id, created_at)',
        )
        .eq('gym_id', gymId)
        .eq('workout_date', value)
        .order('program_id');
    return List<Map<String, dynamic>>.from(rows);
  }
}
