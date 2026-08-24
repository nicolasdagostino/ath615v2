import 'package:supabase_flutter/supabase_flutter.dart';

enum ClassCancellationScope { single, future }

class ClassCancellationImpact {
  const ClassCancellationImpact({
    required this.classesCount,
    required this.bookingsCount,
    required this.waitlistCount,
    required this.creditsToRefund,
  });

  factory ClassCancellationImpact.fromJson(Map<String, dynamic> json) {
    int readCount(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ClassCancellationImpact(
      classesCount: readCount('classes_count'),
      bookingsCount: readCount('bookings_count'),
      waitlistCount: readCount('waitlist_count'),
      creditsToRefund: readCount('credits_to_refund'),
    );
  }

  final int classesCount;
  final int bookingsCount;
  final int waitlistCount;
  final int creditsToRefund;

  bool get hasAffectedMembers => bookingsCount > 0 || waitlistCount > 0;
}

class ClassCancellationService {
  const ClassCancellationService(this._client);

  final SupabaseClient _client;

  Future<ClassCancellationImpact> loadImpact({
    required String classId,
    required ClassCancellationScope scope,
  }) async {
    final response = await _client.rpc(
      'get_class_cancellation_impact',
      params: {'p_class_id': classId, 'p_scope': scope.name},
    );
    final row = response is List
        ? (response.isEmpty ? const <String, dynamic>{} : response.first)
        : response;
    return ClassCancellationImpact.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
  }

  Future<void> cancel({
    required String classId,
    required ClassCancellationScope scope,
  }) async {
    await _client.rpc(
      'admin_cancel_class',
      params: {'p_class_id': classId, 'p_scope': scope.name},
    );
  }
}
