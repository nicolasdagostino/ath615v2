import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> updateClassBookingAttendance({
  required SupabaseClient client,
  required String bookingId,
  required String status,
}) => client
    .from('class_bookings')
    .update({'status': status})
    .eq('id', bookingId);

Future<void> removeClassBookingAsAdmin({
  required SupabaseClient client,
  required String bookingId,
}) async {
  await client.rpc(
    'admin_cancel_class_booking',
    params: {'p_booking_id': bookingId},
  );
  try {
    await client.functions.invoke('send-notifications');
  } catch (_) {
    // Notifications remain queued for the existing scheduler.
  }
}

Future<int> markAllClassAttended({
  required SupabaseClient client,
  required String classId,
}) async {
  final result = await client.rpc(
    'admin_mark_all_class_attended',
    params: {'p_class_id': classId},
  );
  return result is int ? result : int.tryParse(result.toString()) ?? 0;
}
