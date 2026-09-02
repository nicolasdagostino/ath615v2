import 'package:supabase_flutter/supabase_flutter.dart';

enum CoachClassTemporalStatus { upcoming, inProgress, completed }

class CoachBriefing {
  const CoachBriefing({
    required this.localDate,
    required this.timezone,
    required this.classes,
  });

  factory CoachBriefing.fromJson(Map<String, dynamic> json) => CoachBriefing(
    localDate: DateTime.parse(json['local_date'].toString()),
    timezone: json['timezone']?.toString() ?? 'Europe/Madrid',
    classes: List<Map<String, dynamic>>.from(
      json['classes'] as List? ?? const [],
    ).map(CoachBriefingClass.fromJson).toList(),
  );

  final DateTime localDate;
  final String timezone;
  final List<CoachBriefingClass> classes;
}

class CoachBriefingClass {
  const CoachBriefingClass({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.localStartTime,
    required this.durationMinutes,
    required this.capacity,
    required this.coachId,
    required this.coachName,
    required this.coachAvatarUrl,
    required this.programName,
    required this.workoutDescription,
    required this.booked,
    required this.waitlist,
  });

  factory CoachBriefingClass.fromJson(Map<String, dynamic> json) =>
      CoachBriefingClass(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? 'Class',
        startsAt: DateTime.parse(json['starts_at'].toString()),
        localStartTime: json['local_start_time']?.toString() ?? '',
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
        capacity: (json['capacity'] as num?)?.toInt() ?? 0,
        coachId: json['coach_id']?.toString(),
        coachName: json['coach_name']?.toString(),
        coachAvatarUrl: json['coach_avatar_url']?.toString(),
        programName: json['program_name']?.toString(),
        workoutDescription: json['workout_description']?.toString(),
        booked: List<Map<String, dynamic>>.from(
          json['booked'] as List? ?? const [],
        ).map(CoachBriefingAthlete.fromJson).toList(),
        waitlist: List<Map<String, dynamic>>.from(
          json['waitlist'] as List? ?? const [],
        ).map(CoachBriefingWaitlistMember.fromJson).toList(),
      );

  final String id;
  final String title;
  final DateTime startsAt;
  final String localStartTime;
  final int durationMinutes;
  final int capacity;
  final String? coachId;
  final String? coachName;
  final String? coachAvatarUrl;
  final String? programName;
  final String? workoutDescription;
  final List<CoachBriefingAthlete> booked;
  final List<CoachBriefingWaitlistMember> waitlist;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  CoachClassTemporalStatus temporalStatusAt(DateTime now) {
    final instant = now.toUtc();
    if (instant.isBefore(startsAt.toUtc())) {
      return CoachClassTemporalStatus.upcoming;
    }
    if (instant.isBefore(endsAt.toUtc())) {
      return CoachClassTemporalStatus.inProgress;
    }
    return CoachClassTemporalStatus.completed;
  }
}

class CoachBriefingAthlete {
  const CoachBriefingAthlete({
    required this.bookingId,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.isGuest,
    required this.attendanceStatus,
    required this.firstClass,
    required this.membershipUsable,
    required this.membershipPlanType,
    required this.creditsRemaining,
    required this.membershipExpiresAt,
  });

  factory CoachBriefingAthlete.fromJson(Map<String, dynamic> json) =>
      CoachBriefingAthlete(
        bookingId: json['booking_id'].toString(),
        userId: json['user_id']?.toString(),
        name: json['name']?.toString() ?? 'Member',
        avatarUrl: json['avatar_url']?.toString(),
        isGuest: json['is_guest'] == true,
        attendanceStatus: json['attendance_status']?.toString() ?? 'booked',
        firstClass: json['first_class'] == true,
        membershipUsable: json['membership_usable'] == true,
        membershipPlanType: json['membership_plan_type']?.toString(),
        creditsRemaining: (json['credits_remaining'] as num?)?.toInt(),
        membershipExpiresAt: DateTime.tryParse(
          json['membership_expires_at']?.toString() ?? '',
        ),
      );

  final String bookingId;
  final String? userId;
  final String name;
  final String? avatarUrl;
  final bool isGuest;
  final String attendanceStatus;
  final bool firstClass;
  final bool membershipUsable;
  final String? membershipPlanType;
  final int? creditsRemaining;
  final DateTime? membershipExpiresAt;

  bool get hasLowCredits =>
      membershipUsable &&
      membershipPlanType == 'class_pack' &&
      creditsRemaining != null &&
      creditsRemaining! > 0 &&
      creditsRemaining! <= 2;

  bool membershipExpiresWithin(DateTime now, Duration window) {
    if (!membershipUsable || membershipExpiresAt == null) return false;
    final remaining = membershipExpiresAt!.difference(now);
    return remaining > Duration.zero && remaining <= window;
  }

  CoachBriefingAthlete withAttendanceStatus(String status) =>
      CoachBriefingAthlete(
        bookingId: bookingId,
        userId: userId,
        name: name,
        avatarUrl: avatarUrl,
        isGuest: isGuest,
        attendanceStatus: status,
        firstClass: firstClass,
        membershipUsable: membershipUsable,
        membershipPlanType: membershipPlanType,
        creditsRemaining: creditsRemaining,
        membershipExpiresAt: membershipExpiresAt,
      );
}

class CoachBriefingWaitlistMember {
  const CoachBriefingWaitlistMember({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.position,
  });

  factory CoachBriefingWaitlistMember.fromJson(Map<String, dynamic> json) =>
      CoachBriefingWaitlistMember(
        userId: json['user_id'].toString(),
        name: json['name']?.toString() ?? 'Member',
        avatarUrl: json['avatar_url']?.toString(),
        position: (json['position'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String name;
  final String? avatarUrl;
  final int position;
}

abstract interface class CoachBriefingRepository {
  Future<CoachBriefing> loadToday();
  Future<bool> setAttendance({
    required String bookingId,
    required String expectedStatus,
    required String status,
  });
  Future<int> markAllAttended(String classId);
}

class SupabaseCoachBriefingRepository implements CoachBriefingRepository {
  const SupabaseCoachBriefingRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<CoachBriefing> loadToday() async {
    final result = await _client.rpc('get_daily_coach_briefing_with_coach');
    return CoachBriefing.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<bool> setAttendance({
    required String bookingId,
    required String expectedStatus,
    required String status,
  }) async {
    final result = await _client.rpc(
      'set_class_booking_attendance_status',
      params: {
        'p_booking_id': bookingId,
        'p_expected_status': expectedStatus,
        'p_status': status,
      },
    );
    return result == true;
  }

  @override
  Future<int> markAllAttended(String classId) async {
    final result = await _client.rpc(
      'admin_mark_all_class_attended',
      params: {'p_class_id': classId},
    );
    return result is num ? result.toInt() : int.tryParse('$result') ?? 0;
  }
}
