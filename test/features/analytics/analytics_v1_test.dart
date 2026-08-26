import 'dart:async';

import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/features/analytics/data/analytics_repository.dart';
import 'package:ath615v2/features/analytics/domain/analytics_models.dart';
import 'package:ath615v2/features/analytics/presentation/analytics_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localeController.setLanguage('en');
  });

  testWidgets(
    'overview uses one aggregate call and renders four primary KPIs',
    (tester) async {
      final repository = _FakeAnalyticsRepository();
      await _pump(tester, repository);

      expect(repository.overviewCalls, 1);
      expect(repository.attendanceCalls, 0);
      expect(find.text('ACTIVE MEMBERS'), findsOneWidget);
      expect(find.text('ATTENDANCES'), findsAtLeastNWidgets(1));
      expect(find.text('OCCUPANCY'), findsOneWidget);
      expect(find.text('BOOKINGS'), findsAtLeastNWidgets(1));
      expect(find.text('No comparable period'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('period filter reloads only the selected aggregate', (
    tester,
  ) async {
    final repository = _FakeAnalyticsRepository();
    await _pump(tester, repository);

    await tester.tap(find.text('7 DAYS'));
    await tester.pumpAndSettle();
    expect(repository.overviewCalls, 2);
    expect(repository.lastPeriod, AnalyticsPeriod.sevenDays);

    await tester.tap(find.text('ATTENDANCE').first);
    await tester.pumpAndSettle();
    expect(repository.attendanceCalls, 1);
    expect(find.byKey(const ValueKey('analytics-trend-chart')), findsOneWidget);
    expect(find.text('PROGRAMS'), findsOneWidget);
    expect(find.text('TIME SLOTS'), findsOneWidget);
  });

  testWidgets('attendance has a stable empty state', (tester) async {
    final repository = _FakeAnalyticsRepository(emptyAttendance: true);
    await _pump(tester, repository);
    await tester.tap(find.text('ATTENDANCE').first);
    await tester.pumpAndSettle();

    expect(find.text('There is no activity in this period.'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  testWidgets('Analytics V1 strings are localized to Spanish', (tester) async {
    await localeController.setLanguage('es');
    await _pump(tester, _FakeAnalyticsRepository());

    expect(find.text('RESUMEN'), findsOneWidget);
    expect(find.text('ASISTENCIAS'), findsAtLeastNWidgets(1));
    expect(find.text('MIEMBROS ACTIVOS'), findsOneWidget);
    expect(find.text('Sin periodo comparable'), findsAtLeastNWidgets(1));
  });

  testWidgets('loading and error states are explicit', (tester) async {
    final completer = Completer<AnalyticsOverview>();
    final repository = _FakeAnalyticsRepository(overviewCompleter: completer);
    await _pump(tester, repository, settle: false);
    expect(find.text('Loading analytics…'), findsOneWidget);

    completer.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Analytics could not be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('overview and attendance stay overflow-free at 320 px', (
    tester,
  ) async {
    final repository = _FakeAnalyticsRepository();
    await _pump(tester, repository, size: const Size(320, 700));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('ATTENDANCE').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('LOWEST OCCUPANCY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AnalyticsRepository repository, {
  Size size = const Size(390, 844),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [AnalyticsView(repository: repository)],
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

class _FakeAnalyticsRepository implements AnalyticsRepository {
  _FakeAnalyticsRepository({
    this.emptyAttendance = false,
    this.overviewCompleter,
  });

  final bool emptyAttendance;
  final Completer<AnalyticsOverview>? overviewCompleter;
  int overviewCalls = 0;
  int attendanceCalls = 0;
  AnalyticsPeriod? lastPeriod;

  @override
  Future<AnalyticsOverview> loadOverview(AnalyticsPeriod period) {
    overviewCalls++;
    lastPeriod = period;
    if (overviewCompleter != null) return overviewCompleter!.future;
    return Future.value(_overview);
  }

  @override
  Future<AttendanceAnalytics> loadAttendance(AnalyticsPeriod period) async {
    attendanceCalls++;
    lastPeriod = period;
    return emptyAttendance ? _emptyAttendance : _attendance;
  }
}

final _overview = AnalyticsOverview(
  timezone: 'Europe/Madrid',
  from: DateTime(2026, 8, 1),
  toExclusive: DateTime(2026, 8, 28),
  current: const AnalyticsMetricSet(
    activeMembers: 42,
    newMembers: 4,
    deliveredClasses: 21,
    bookings: 180,
    attendances: 160,
    noShows: 8,
    globalOccupancy: 72.5,
    averageClassOccupancy: 68.2,
  ),
  previous: const AnalyticsMetricSet(
    activeMembers: 0,
    newMembers: 0,
    deliveredClasses: 20,
    bookings: 160,
    attendances: 140,
    noShows: 10,
    globalOccupancy: 65,
    averageClassOccupancy: 63,
  ),
);

final _attendance = AttendanceAnalytics(
  trend: List.generate(
    7,
    (index) => AnalyticsTrendPoint(
      date: DateTime(2026, 8, 20 + index),
      bookings: 8 + index,
      attendances: 6 + index,
      noShows: 1,
      occupancy: 60 + index.toDouble(),
    ),
  ),
  programs: const [
    AnalyticsBreakdownRow(
      label: 'CrossFit',
      bookings: 40,
      attendances: 35,
      occupancy: 80,
    ),
  ],
  weekdays: const [
    AnalyticsBreakdownRow(
      label: '',
      weekday: 1,
      bookings: 40,
      attendances: 35,
      occupancy: 80,
    ),
  ],
  hours: const [
    AnalyticsBreakdownRow(
      label: '',
      hour: 19,
      bookings: 40,
      attendances: 35,
      occupancy: 80,
    ),
  ],
  mostOccupiedClasses: [
    AnalyticsClassRow(
      id: 'class-a',
      programName: 'CrossFit',
      date: DateTime(2026, 8, 26),
      hour: 19,
      capacity: 16,
      bookings: 16,
      attendances: 15,
      occupancy: 100,
    ),
  ],
  leastOccupiedClasses: [
    AnalyticsClassRow(
      id: 'class-b',
      programName: 'Weightlifting',
      date: DateTime(2026, 8, 25),
      hour: 8,
      capacity: 16,
      bookings: 4,
      attendances: 4,
      occupancy: 25,
    ),
  ],
);

final _emptyAttendance = AttendanceAnalytics(
  trend: List.generate(
    7,
    (index) => AnalyticsTrendPoint(
      date: DateTime(2026, 8, 20 + index),
      bookings: 0,
      attendances: 0,
      noShows: 0,
      occupancy: null,
    ),
  ),
  programs: const [],
  weekdays: const [],
  hours: const [],
  mostOccupiedClasses: const [],
  leastOccupiedClasses: const [],
);
