import 'package:supabase_flutter/supabase_flutter.dart';

const int bookingHistoryPageSize = 15;

abstract interface class MyReservationsDataSource {
  Future<List<Map<String, dynamic>>> loadUpcoming();

  Future<List<Map<String, dynamic>>> loadHistory({
    required int offset,
    int limit = bookingHistoryPageSize,
  });
}

class SupabaseMyReservationsDataSource implements MyReservationsDataSource {
  SupabaseMyReservationsDataSource(this.client);

  final SupabaseClient client;

  static const _classFields =
      'id,title,starts_at,duration_minutes,capacity,recurring_id,'
      'program_id,coach_id,programs(name,image_url),'
      'coach:profiles!classes_coach_id_fkey(full_name)';

  String get _userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Not authenticated');
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> loadUpcoming() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final userId = _userId;
    final booked =
        List<Map<String, dynamic>>.from(
          await client
              .from('classes')
              .select(
                '$_classFields,class_bookings!inner(id,status,user_id,created_at)',
              )
              .eq('class_bookings.user_id', userId)
              .neq('class_bookings.status', 'cancelled')
              .gte('starts_at', now)
              .order('starts_at', ascending: true),
        ).map((row) {
          final bookings = List<Map<String, dynamic>>.from(
            row['class_bookings'] as List? ?? const [],
          );
          return {
            ...row,
            'reservation_kind': 'booking',
            'reservation_status': bookings.isEmpty
                ? 'booked'
                : bookings.first['status']?.toString() ?? 'booked',
          };
        }).toList();

    final waitlisted = List<Map<String, dynamic>>.from(
      await client
          .from('classes')
          .select('$_classFields,class_waitlist!inner(id,user_id,created_at)')
          .eq('class_waitlist.user_id', userId)
          .gte('starts_at', now)
          .order('starts_at', ascending: true),
    ).map((row) => {...row, 'reservation_kind': 'waitlist'}).toList();

    final waitlistClassIds = waitlisted
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList();
    if (waitlistClassIds.isNotEmpty) {
      final rows = List<Map<String, dynamic>>.from(
        await client
            .from('class_waitlist')
            .select('class_id,user_id,created_at')
            .inFilter('class_id', waitlistClassIds)
            .order('class_id')
            .order('created_at'),
      );
      final positions = <String, int>{};
      final counts = <String, int>{};
      for (final row in rows) {
        final classId = row['class_id']?.toString();
        if (classId == null) continue;
        final position = (counts[classId] ?? 0) + 1;
        counts[classId] = position;
        if (row['user_id']?.toString() == userId) positions[classId] = position;
      }
      for (final row in waitlisted) {
        row['waitlist_position'] = positions[row['id']?.toString()];
      }
    }

    final result = [...booked, ...waitlisted];
    result.sort(
      (a, b) => DateTime.parse(
        a['starts_at'].toString(),
      ).compareTo(DateTime.parse(b['starts_at'].toString())),
    );
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> loadHistory({
    required int offset,
    int limit = bookingHistoryPageSize,
  }) async {
    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('classes')
          .select(
            '$_classFields,class_bookings!inner(id,status,user_id,created_at)',
          )
          .eq('class_bookings.user_id', _userId)
          .lt('starts_at', DateTime.now().toUtc().toIso8601String())
          .order('starts_at', ascending: false)
          .range(offset, offset + limit - 1),
    );
    return rows.map((row) {
      final bookings = List<Map<String, dynamic>>.from(
        row['class_bookings'] as List? ?? const [],
      );
      return {
        ...row,
        'reservation_kind': 'booking',
        'reservation_status': bookings.isEmpty
            ? 'booked'
            : bookings.first['status']?.toString() ?? 'booked',
      };
    }).toList();
  }
}
