import 'package:supabase_flutter/supabase_flutter.dart';

const workoutNotificationTypes = <String>{
  'workout_published',
  'post_score_reminder',
  'daily_workout',
  'daily_workout_published',
  'workout',
};

bool isWorkoutNotification({
  required Object? type,
  required Map<String, dynamic> data,
}) {
  final normalizedType = type?.toString().trim().toLowerCase();
  if (normalizedType != null &&
      workoutNotificationTypes.contains(normalizedType)) {
    return true;
  }
  final source = data['source']?.toString().trim().toLowerCase();
  return source != null && workoutNotificationTypes.contains(source);
}

DateTime? parseNotificationDate(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _formatDate(parsed) != value) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String wodDestination(DateTime date) =>
    '/app?section=wod&date=${_formatDate(date)}';

Future<DateTime?> resolveWorkoutNotificationDate({
  required SupabaseClient client,
  required Map<String, dynamic> data,
}) async {
  final embedded = parseNotificationDate(
    data['workoutDate'] ?? data['workout_date'],
  );
  if (embedded != null) return embedded;

  final workoutId = data['workoutId'] ?? data['workout_id'];
  if (workoutId == null || workoutId.toString().trim().isEmpty) return null;

  try {
    final workout = await client
        .from('workouts')
        .select('workout_date')
        .eq('id', workoutId.toString())
        .maybeSingle();
    return parseNotificationDate(workout?['workout_date']);
  } catch (_) {
    return null;
  }
}

Future<String> resolveWorkoutDestination({
  required SupabaseClient client,
  required Map<String, dynamic> data,
  DateTime? fallbackDate,
}) async {
  final date = await resolveWorkoutNotificationDate(client: client, data: data);
  return wodDestination(date ?? fallbackDate ?? DateTime.now());
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
