import 'package:supabase_flutter/supabase_flutter.dart';

class MembershipOperationBooking {
  const MembershipOperationBooking({
    required this.id,
    required this.classId,
    required this.title,
    required this.startsAt,
  });

  final String id;
  final String classId;
  final String title;
  final DateTime? startsAt;

  factory MembershipOperationBooking.fromJson(Map<String, dynamic> json) =>
      MembershipOperationBooking(
        id: json['booking_id']?.toString() ?? '',
        classId: json['class_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        startsAt: DateTime.tryParse(
          json['starts_at']?.toString() ?? '',
        )?.toLocal(),
      );
}

class MembershipOperationPreview {
  const MembershipOperationPreview({
    required this.membershipId,
    required this.planName,
    required this.planType,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.creditsRemaining,
    required this.creditsTotal,
    required this.attendedCount,
    required this.noShowCount,
    required this.futureBookedCount,
    required this.conflictingBookingCount,
    required this.futureBookings,
    required this.hasChainedUnlimited,
  });

  final String membershipId;
  final String planName;
  final String planType;
  final String status;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? creditsRemaining;
  final int? creditsTotal;
  final int attendedCount;
  final int noShowCount;
  final int futureBookedCount;
  final int conflictingBookingCount;
  final List<MembershipOperationBooking> futureBookings;
  final bool hasChainedUnlimited;

  bool get isUnlimited => planType == 'unlimited';
  bool get hasRecordedUsage => attendedCount > 0 || noShowCount > 0;

  factory MembershipOperationPreview.fromJson(Map<String, dynamic> json) {
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;
    final rawBookings = json['future_bookings'];
    return MembershipOperationPreview(
      membershipId: json['membership_id']?.toString() ?? '',
      planName: json['plan_name']?.toString() ?? '',
      planType: json['plan_type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      startsAt: DateTime.tryParse(
        json['starts_at']?.toString() ?? '',
      )?.toLocal(),
      expiresAt: DateTime.tryParse(
        json['expires_at']?.toString() ?? '',
      )?.toLocal(),
      creditsRemaining: (json['credits_remaining'] as num?)?.toInt(),
      creditsTotal: (json['credits_total'] as num?)?.toInt(),
      attendedCount: integer('attended_count'),
      noShowCount: integer('no_show_count'),
      futureBookedCount: integer('future_booked_count'),
      conflictingBookingCount: integer('conflicting_booking_count'),
      futureBookings: rawBookings is List
          ? rawBookings
                .whereType<Map>()
                .map(
                  (value) => MembershipOperationBooking.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList()
          : const [],
      hasChainedUnlimited: json['has_chained_unlimited'] == true,
    );
  }
}

abstract class MembershipOperationsDataSource {
  Future<MembershipOperationPreview> preview(
    String membershipId, {
    DateTime? newExpiration,
  });

  Future<void> voidMembership({
    required String membershipId,
    required String reason,
    String? note,
  });

  Future<void> cancelMembership({
    required String membershipId,
    required String reason,
    String? note,
  });

  Future<void> changeExpiration({
    required String membershipId,
    required DateTime newExpiration,
    required String reason,
    String? note,
    required bool cancelConflictingBookings,
  });
}

class SupabaseMembershipOperationsRepository
    implements MembershipOperationsDataSource {
  SupabaseMembershipOperationsRepository(this.client);

  final SupabaseClient client;

  @override
  Future<MembershipOperationPreview> preview(
    String membershipId, {
    DateTime? newExpiration,
  }) async {
    final value = await client.rpc(
      'get_member_membership_operation_preview',
      params: {
        'p_membership_id': membershipId,
        'p_new_expires_at': newExpiration?.toUtc().toIso8601String(),
      },
    );
    return MembershipOperationPreview.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
  }

  @override
  Future<void> voidMembership({
    required String membershipId,
    required String reason,
    String? note,
  }) => client.rpc<void>(
    'void_member_membership',
    params: {
      'p_membership_id': membershipId,
      'p_reason': reason,
      'p_reason_note': note,
    },
  );

  @override
  Future<void> cancelMembership({
    required String membershipId,
    required String reason,
    String? note,
  }) => client.rpc<void>(
    'cancel_member_membership',
    params: {
      'p_membership_id': membershipId,
      'p_reason': reason,
      'p_reason_note': note,
    },
  );

  @override
  Future<void> changeExpiration({
    required String membershipId,
    required DateTime newExpiration,
    required String reason,
    String? note,
    required bool cancelConflictingBookings,
  }) => client.rpc<void>(
    'change_member_membership_expiration',
    params: {
      'p_membership_id': membershipId,
      'p_new_expires_at': newExpiration.toUtc().toIso8601String(),
      'p_reason': reason,
      'p_reason_note': note,
      'p_cancel_conflicting_bookings': cancelConflictingBookings,
    },
  );
}
