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

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map? ?? const {});

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

double? _doubleOrNull(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
