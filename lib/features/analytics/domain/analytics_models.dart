enum AnalyticsPeriod {
  sevenDays,
  thirtyDays,
  thisMonth,
  previousMonth,
  threeMonths,
}

extension AnalyticsPeriodContract on AnalyticsPeriod {
  String get apiValue => switch (this) {
    AnalyticsPeriod.sevenDays => '7d',
    AnalyticsPeriod.thirtyDays => '30d',
    AnalyticsPeriod.thisMonth => 'this_month',
    AnalyticsPeriod.previousMonth => 'previous_month',
    AnalyticsPeriod.threeMonths => '3m',
  };
}

class AnalyticsMetricSet {
  const AnalyticsMetricSet({
    required this.activeMembers,
    required this.newMembers,
    required this.deliveredClasses,
    required this.bookings,
    required this.attendances,
    required this.noShows,
    required this.globalOccupancy,
    required this.averageClassOccupancy,
  });

  factory AnalyticsMetricSet.fromJson(Map<String, dynamic> json) =>
      AnalyticsMetricSet(
        activeMembers: _int(json['activeMembers']),
        newMembers: _int(json['newMembers']),
        deliveredClasses: _int(json['deliveredClasses']),
        bookings: _int(json['bookings']),
        attendances: _int(json['attendances']),
        noShows: _int(json['noShows']),
        globalOccupancy: _doubleOrNull(json['globalOccupancy']),
        averageClassOccupancy: _doubleOrNull(json['averageClassOccupancy']),
      );

  final int activeMembers;
  final int newMembers;
  final int deliveredClasses;
  final int bookings;
  final int attendances;
  final int noShows;
  final double? globalOccupancy;
  final double? averageClassOccupancy;
}

class AnalyticsOverview {
  const AnalyticsOverview({
    required this.timezone,
    required this.from,
    required this.toExclusive,
    required this.current,
    required this.previous,
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) {
    final period = _map(json['period']);
    return AnalyticsOverview(
      timezone: period['timezone']?.toString() ?? '',
      from: DateTime.parse(period['from'].toString()),
      toExclusive: DateTime.parse(period['toExclusive'].toString()),
      current: AnalyticsMetricSet.fromJson(_map(json['current'])),
      previous: AnalyticsMetricSet.fromJson(_map(json['previous'])),
    );
  }

  final String timezone;
  final DateTime from;
  final DateTime toExclusive;
  final AnalyticsMetricSet current;
  final AnalyticsMetricSet previous;
}

class AnalyticsTrendPoint {
  const AnalyticsTrendPoint({
    required this.date,
    required this.bookings,
    required this.attendances,
    required this.noShows,
    required this.occupancy,
  });

  factory AnalyticsTrendPoint.fromJson(Map<String, dynamic> json) =>
      AnalyticsTrendPoint(
        date: DateTime.parse(json['date'].toString()),
        bookings: _int(json['bookings']),
        attendances: _int(json['attendances']),
        noShows: _int(json['noShows']),
        occupancy: _doubleOrNull(json['occupancy']),
      );

  final DateTime date;
  final int bookings;
  final int attendances;
  final int noShows;
  final double? occupancy;
}

class AnalyticsBreakdownRow {
  const AnalyticsBreakdownRow({
    required this.label,
    required this.bookings,
    required this.attendances,
    required this.occupancy,
    this.weekday,
    this.hour,
  });

  final String label;
  final int bookings;
  final int attendances;
  final double? occupancy;
  final int? weekday;
  final int? hour;
}

class AnalyticsClassRow {
  const AnalyticsClassRow({
    required this.id,
    required this.programName,
    required this.date,
    required this.hour,
    required this.capacity,
    required this.bookings,
    required this.attendances,
    required this.occupancy,
  });

  factory AnalyticsClassRow.fromJson(Map<String, dynamic> json) =>
      AnalyticsClassRow(
        id: json['classId']?.toString() ?? '',
        programName: json['programName']?.toString() ?? '—',
        date: DateTime.parse(json['date'].toString()),
        hour: _int(json['hour']),
        capacity: _int(json['capacity']),
        bookings: _int(json['bookings']),
        attendances: _int(json['attendances']),
        occupancy: _doubleOrNull(json['occupancy']),
      );

  final String id;
  final String programName;
  final DateTime date;
  final int hour;
  final int capacity;
  final int bookings;
  final int attendances;
  final double? occupancy;
}

class AttendanceAnalytics {
  const AttendanceAnalytics({
    required this.trend,
    required this.programs,
    required this.weekdays,
    required this.hours,
    required this.mostOccupiedClasses,
    required this.leastOccupiedClasses,
  });

  factory AttendanceAnalytics.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((row) => _map(row))
            .toList();

    return AttendanceAnalytics(
      trend: rows('trend').map(AnalyticsTrendPoint.fromJson).toList(),
      programs: rows('programs')
          .map(
            (row) => AnalyticsBreakdownRow(
              label: row['programName']?.toString() ?? '—',
              bookings: _int(row['bookings']),
              attendances: _int(row['attendances']),
              occupancy: _doubleOrNull(row['occupancy']),
            ),
          )
          .toList(),
      weekdays: rows('weekdays')
          .map(
            (row) => AnalyticsBreakdownRow(
              label: '',
              weekday: _int(row['weekday']),
              bookings: _int(row['bookings']),
              attendances: _int(row['attendances']),
              occupancy: _doubleOrNull(row['occupancy']),
            ),
          )
          .toList(),
      hours: rows('hours')
          .map(
            (row) => AnalyticsBreakdownRow(
              label: '',
              hour: _int(row['hour']),
              bookings: _int(row['bookings']),
              attendances: _int(row['attendances']),
              occupancy: _doubleOrNull(row['occupancy']),
            ),
          )
          .toList(),
      mostOccupiedClasses: rows(
        'mostOccupiedClasses',
      ).map(AnalyticsClassRow.fromJson).toList(),
      leastOccupiedClasses: rows(
        'leastOccupiedClasses',
      ).map(AnalyticsClassRow.fromJson).toList(),
    );
  }

  final List<AnalyticsTrendPoint> trend;
  final List<AnalyticsBreakdownRow> programs;
  final List<AnalyticsBreakdownRow> weekdays;
  final List<AnalyticsBreakdownRow> hours;
  final List<AnalyticsClassRow> mostOccupiedClasses;
  final List<AnalyticsClassRow> leastOccupiedClasses;

  bool get isEmpty =>
      programs.isEmpty &&
      mostOccupiedClasses.isEmpty &&
      trend.every(
        (point) =>
            point.bookings == 0 && point.attendances == 0 && point.noShows == 0,
      );
}

class MembershipAnalytics {
  const MembershipAnalytics({
    required this.snapshot,
    required this.created,
    required this.previousCreated,
    required this.credits,
    required this.plans,
  });

  factory MembershipAnalytics.fromJson(Map<String, dynamic> json) {
    final activity = _map(json['activity']);
    return MembershipAnalytics(
      snapshot: MembershipSnapshot.fromJson(_map(json['snapshot'])),
      created: _int(activity['created']),
      previousCreated: _int(activity['previousCreated']),
      credits: MembershipCreditAnalytics.fromJson(_map(json['credits'])),
      plans: (json['plans'] as List<dynamic>? ?? const [])
          .map((row) => MembershipPlanAnalytics.fromJson(_map(row)))
          .toList(),
    );
  }

  final MembershipSnapshot snapshot;
  final int created;
  final int previousCreated;
  final MembershipCreditAnalytics credits;
  final List<MembershipPlanAnalytics> plans;

  bool get isEmpty => snapshot.total == 0 && created == 0 && plans.isEmpty;
}

class MembershipSnapshot {
  const MembershipSnapshot({
    required this.active,
    required this.activePacks,
    required this.activeUnlimited,
    required this.scheduled,
    required this.exhausted,
    required this.expired,
    required this.cancelled,
    required this.replaced,
  });

  factory MembershipSnapshot.fromJson(Map<String, dynamic> json) =>
      MembershipSnapshot(
        active: _int(json['active']),
        activePacks: _int(json['activePacks']),
        activeUnlimited: _int(json['activeUnlimited']),
        scheduled: _int(json['scheduled']),
        exhausted: _int(json['exhausted']),
        expired: _int(json['expired']),
        cancelled: _int(json['cancelled']),
        replaced: _int(json['replaced']),
      );

  final int active;
  final int activePacks;
  final int activeUnlimited;
  final int scheduled;
  final int exhausted;
  final int expired;
  final int cancelled;
  final int replaced;

  int get total =>
      active + scheduled + exhausted + expired + cancelled + replaced;
}

class MembershipCreditAnalytics {
  const MembershipCreditAnalytics({
    required this.purchasedGranted,
    required this.assignedGranted,
    required this.consumed,
    required this.refunded,
    required this.netConsumed,
    required this.currentRemaining,
    required this.expiredUnused,
    required this.unclassifiedLogs,
  });

  factory MembershipCreditAnalytics.fromJson(Map<String, dynamic> json) =>
      MembershipCreditAnalytics(
        purchasedGranted: _int(json['purchasedGranted']),
        assignedGranted: _int(json['assignedGranted']),
        consumed: _int(json['consumed']),
        refunded: _int(json['refunded']),
        netConsumed: _int(json['netConsumed']),
        currentRemaining: _int(json['currentRemaining']),
        expiredUnused: _int(json['expiredUnused']),
        unclassifiedLogs: _int(json['unclassifiedLogs']),
      );

  final int purchasedGranted;
  final int assignedGranted;
  final int consumed;
  final int refunded;
  final int netConsumed;
  final int currentRemaining;
  final int expiredUnused;
  final int unclassifiedLogs;
}

class MembershipPlanAnalytics {
  const MembershipPlanAnalytics({
    required this.id,
    required this.name,
    required this.membershipsCreated,
    required this.activeNow,
    required this.paidSales,
    required this.directAssignments,
  });

  factory MembershipPlanAnalytics.fromJson(Map<String, dynamic> json) =>
      MembershipPlanAnalytics(
        id: json['planId']?.toString(),
        name: json['planName']?.toString() ?? '—',
        membershipsCreated: _int(json['membershipsCreated']),
        activeNow: _int(json['activeNow']),
        paidSales: _int(json['paidSales']),
        directAssignments: _int(json['directAssignments']),
      );

  final String? id;
  final String name;
  final int membershipsCreated;
  final int activeNow;
  final int paidSales;
  final int directAssignments;
}

class RevenueAnalytics {
  const RevenueAnalytics({
    required this.currencies,
    required this.methods,
    required this.plans,
    required this.trend,
    required this.states,
    required this.excluded,
  });

  factory RevenueAnalytics.fromJson(Map<String, dynamic> json) =>
      RevenueAnalytics(
        currencies: (json['currencies'] as List<dynamic>? ?? const [])
            .map((row) => RevenueCurrencyAnalytics.fromJson(_map(row)))
            .toList(),
        methods: (json['methods'] as List<dynamic>? ?? const [])
            .map((row) => RevenueMethodAnalytics.fromJson(_map(row)))
            .toList(),
        plans: (json['plans'] as List<dynamic>? ?? const [])
            .map((row) => RevenuePlanAnalytics.fromJson(_map(row)))
            .toList(),
        trend: (json['trend'] as List<dynamic>? ?? const [])
            .map((row) => RevenueTrendPoint.fromJson(_map(row)))
            .toList(),
        states: RevenueStateCounts.fromJson(_map(json['states'])),
        excluded: RevenueExcludedCounts.fromJson(_map(json['excluded'])),
      );

  final List<RevenueCurrencyAnalytics> currencies;
  final List<RevenueMethodAnalytics> methods;
  final List<RevenuePlanAnalytics> plans;
  final List<RevenueTrendPoint> trend;
  final RevenueStateCounts states;
  final RevenueExcludedCounts excluded;

  bool get isEmpty => currencies.isEmpty;
}

class RevenueCurrencyAnalytics {
  const RevenueCurrencyAnalytics({
    required this.currency,
    required this.totalMinor,
    required this.paymentCount,
    required this.averageMinor,
    required this.previousTotalMinor,
    required this.previousPaymentCount,
    required this.previousAverageMinor,
  });

  factory RevenueCurrencyAnalytics.fromJson(Map<String, dynamic> json) =>
      RevenueCurrencyAnalytics(
        currency: json['currency']?.toString() ?? '',
        totalMinor: _int(json['totalMinor']),
        paymentCount: _int(json['paymentCount']),
        averageMinor: _int(json['averageMinor']),
        previousTotalMinor: _int(json['previousTotalMinor']),
        previousPaymentCount: _int(json['previousPaymentCount']),
        previousAverageMinor: _intOrNull(json['previousAverageMinor']),
      );

  final String currency;
  final int totalMinor;
  final int paymentCount;
  final int averageMinor;
  final int previousTotalMinor;
  final int previousPaymentCount;
  final int? previousAverageMinor;
}

class RevenueMethodAnalytics {
  const RevenueMethodAnalytics({
    required this.currency,
    required this.method,
    required this.totalMinor,
    required this.paymentCount,
  });
  factory RevenueMethodAnalytics.fromJson(Map<String, dynamic> json) =>
      RevenueMethodAnalytics(
        currency: json['currency']?.toString() ?? '',
        method: json['method']?.toString() ?? '',
        totalMinor: _int(json['totalMinor']),
        paymentCount: _int(json['paymentCount']),
      );
  final String currency;
  final String method;
  final int totalMinor;
  final int paymentCount;
}

class RevenuePlanAnalytics {
  const RevenuePlanAnalytics({
    required this.currency,
    required this.id,
    required this.name,
    required this.revenueMinor,
    required this.paymentCount,
    required this.averageMinor,
    required this.revenueShare,
  });
  factory RevenuePlanAnalytics.fromJson(Map<String, dynamic> json) =>
      RevenuePlanAnalytics(
        currency: json['currency']?.toString() ?? '',
        id: json['planId']?.toString(),
        name: json['planName']?.toString() ?? '—',
        revenueMinor: _int(json['revenueMinor']),
        paymentCount: _int(json['paymentCount']),
        averageMinor: _int(json['averageMinor']),
        revenueShare: _doubleOrNull(json['revenueShare']),
      );
  final String currency;
  final String? id;
  final String name;
  final int revenueMinor;
  final int paymentCount;
  final int averageMinor;
  final double? revenueShare;
}

class RevenueTrendPoint {
  const RevenueTrendPoint({
    required this.date,
    required this.currency,
    required this.totalMinor,
    required this.paymentCount,
  });
  factory RevenueTrendPoint.fromJson(Map<String, dynamic> json) =>
      RevenueTrendPoint(
        date: DateTime.parse(json['bucketStart'].toString()),
        currency: json['currency']?.toString() ?? '',
        totalMinor: _int(json['totalMinor']),
        paymentCount: _int(json['paymentCount']),
      );
  final DateTime date;
  final String currency;
  final int totalMinor;
  final int paymentCount;
}

class RevenueStateCounts {
  const RevenueStateCounts({
    required this.paid,
    required this.pending,
    required this.failed,
    required this.cancelled,
  });
  factory RevenueStateCounts.fromJson(Map<String, dynamic> json) =>
      RevenueStateCounts(
        paid: _int(json['paid']),
        pending: _int(json['pending']),
        failed: _int(json['failed']),
        cancelled: _int(json['cancelled']),
      );
  final int paid;
  final int pending;
  final int failed;
  final int cancelled;
}

class RevenueExcludedCounts {
  const RevenueExcludedCounts({
    required this.paidMissingAudit,
    required this.legacyApprovedPending,
    required this.unclassifiedManualMethod,
  });
  factory RevenueExcludedCounts.fromJson(Map<String, dynamic> json) =>
      RevenueExcludedCounts(
        paidMissingAudit: _int(json['paidMissingAudit']),
        legacyApprovedPending: _int(json['legacyApprovedPending']),
        unclassifiedManualMethod: _int(json['unclassifiedManualMethod']),
      );
  final int paidMissingAudit;
  final int legacyApprovedPending;
  final int unclassifiedManualMethod;
}

enum RetentionSegment {
  noAttendance7('no_attendance_7'),
  noAttendance14('no_attendance_14'),
  noAttendance30('no_attendance_30'),
  activeMembershipNoRecentUse('active_membership_no_recent_use'),
  noUsableMembership('no_usable_membership'),
  expiringSoon('expiring_soon'),
  lowCredits('low_credits'),
  firstClassNoReturn('first_class_no_return'),
  inactiveRecent('inactive_recent'),
  repeatedNoShows('repeated_no_shows');

  const RetentionSegment(this.apiValue);
  final String apiValue;
}

class RetentionSummary {
  const RetentionSummary({required this.timezone, required this.counts});

  factory RetentionSummary.fromJson(Map<String, dynamic> json) {
    final values = _map(json['segments']);
    return RetentionSummary(
      timezone: json['timezone']?.toString() ?? '',
      counts: {
        for (final segment in RetentionSegment.values)
          segment: _int(values[segment.apiValue]),
      },
    );
  }

  final String timezone;
  final Map<RetentionSegment, int> counts;
  int countFor(RetentionSegment segment) => counts[segment] ?? 0;
}

class RetentionMember {
  const RetentionMember({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.lastAttendedAt,
    required this.attendancesCount,
    required this.usableMembership,
    required this.membershipPlanName,
    required this.membershipPlanType,
    required this.creditsRemaining,
    required this.membershipEndsAt,
    required this.hasFutureBooking,
    required this.futureBookingAt,
    required this.noShowCount30d,
  });

  factory RetentionMember.fromJson(Map<String, dynamic> json) =>
      RetentionMember(
        userId: json['userId']?.toString() ?? '',
        name: json['name']?.toString() ?? '—',
        avatarUrl: json['avatarUrl']?.toString(),
        lastAttendedAt: _dateOrNull(json['lastAttendedAt']),
        attendancesCount: _int(json['attendancesCount']),
        usableMembership: json['usableMembership'] == true,
        membershipPlanName: json['membershipPlanName']?.toString(),
        membershipPlanType: json['membershipPlanType']?.toString(),
        creditsRemaining: _intOrNull(json['creditsRemaining']),
        membershipEndsAt: _dateOrNull(json['membershipEndsAt']),
        hasFutureBooking: json['hasFutureBooking'] == true,
        futureBookingAt: _dateOrNull(json['futureBookingAt']),
        noShowCount30d: _int(json['noShowCount30d']),
      );

  final String userId;
  final String name;
  final String? avatarUrl;
  final DateTime? lastAttendedAt;
  final int attendancesCount;
  final bool usableMembership;
  final String? membershipPlanName;
  final String? membershipPlanType;
  final int? creditsRemaining;
  final DateTime? membershipEndsAt;
  final bool hasFutureBooking;
  final DateTime? futureBookingAt;
  final int noShowCount30d;

  Map<String, dynamic> get memberDetailData => {
    'id': userId,
    'full_name': name,
    'avatar_url': avatarUrl,
    'role': 'athlete',
    'is_active': true,
  };
}

class RetentionPage {
  const RetentionPage({
    required this.segment,
    required this.totalCount,
    required this.limit,
    required this.offset,
    required this.items,
  });

  factory RetentionPage.fromJson(Map<String, dynamic> json) => RetentionPage(
    segment: RetentionSegment.values.firstWhere(
      (segment) => segment.apiValue == json['segment']?.toString(),
    ),
    totalCount: _int(json['totalCount']),
    limit: _int(json['limit']),
    offset: _int(json['offset']),
    items: (json['items'] as List<dynamic>? ?? const [])
        .map((row) => RetentionMember.fromJson(_map(row)))
        .toList(),
  );

  final RetentionSegment segment;
  final int totalCount;
  final int limit;
  final int offset;
  final List<RetentionMember> items;
  bool get hasMore => offset + items.length < totalCount;
}

class RetentionCommunicationResult {
  const RetentionCommunicationResult({
    required this.count,
    required this.communicationId,
  });
  factory RetentionCommunicationResult.fromJson(Map<String, dynamic> json) =>
      RetentionCommunicationResult(
        count: _int(json['count']),
        communicationId: json['communicationId']?.toString() ?? '',
      );
  final int count;
  final String communicationId;
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map? ?? const {});

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

int? _intOrNull(Object? value) => value == null
    ? null
    : value is num
    ? value.toInt()
    : int.tryParse(value.toString());

double? _doubleOrNull(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

DateTime? _dateOrNull(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
