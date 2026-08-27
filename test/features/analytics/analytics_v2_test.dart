import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
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

  testWidgets('V2 exposes only the four implemented sections', (tester) async {
    await _pump(tester, _FakeV2Repository());
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('ATTENDANCE'), findsOneWidget);
    expect(find.text('MEMBERSHIPS'), findsOneWidget);
    expect(find.text('REVENUE'), findsOneWidget);
    expect(find.text('RETENTION'), findsNothing);
  });

  testWidgets(
    'memberships uses one aggregate and renders snapshot and credits',
    (tester) async {
      final repository = _FakeV2Repository();
      await _pump(tester, repository);
      await _selectSection(tester, 'MEMBERSHIPS');

      expect(repository.membershipCalls, 1);
      expect(
        find.byKey(const ValueKey('analytics-memberships-content')),
        findsOneWidget,
      );
      expect(find.text('ACTIVE PACKS'), findsOneWidget);
      expect(find.text('PACKS VS UNLIMITED'), findsOneWidget);
      expect(find.text('Granted by purchase'), findsOneWidget);
      expect(find.textContaining('2 sold'), findsOneWidget);
    },
  );

  testWidgets('revenue keeps currencies separate and renders real methods', (
    tester,
  ) async {
    final repository = _FakeV2Repository();
    await _pump(tester, repository);
    await _selectSection(tester, 'REVENUE');

    expect(repository.revenueCalls, 1);
    expect(
      find.byKey(const ValueKey('analytics-revenue-content')),
      findsOneWidget,
    );
    expect(find.text('EUR'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
    expect(find.text('Card'), findsWidgets);
    expect(find.byKey(const ValueKey('analytics-revenue-chart')), findsWidgets);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  testWidgets('membership and revenue empty states are explicit', (
    tester,
  ) async {
    final repository = _FakeV2Repository(empty: true);
    await _pump(tester, repository);
    await _selectSection(tester, 'MEMBERSHIPS');
    expect(find.text('There are no memberships to analyze.'), findsOneWidget);

    await _selectSection(tester, 'REVENUE');
    expect(
      find.text('There are no confirmed payments in this period.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'V2 remains overflow-free at 320 px and reloads selected period',
    (tester) async {
      final repository = _FakeV2Repository();
      await _pump(tester, repository, size: const Size(320, 700));
      await _selectSection(tester, 'MEMBERSHIPS');
      await tester.tap(find.text('7 DAYS'));
      await tester.pumpAndSettle();
      expect(repository.membershipCalls, 2);
      expect(repository.lastPeriod, AnalyticsPeriod.sevenDays);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('V2 strings are localized to Spanish', (tester) async {
    await localeController.setLanguage('es');
    await _pump(tester, _FakeV2Repository());
    expect(find.text('MEMBRESÍAS'), findsOneWidget);
    expect(find.text('INGRESOS'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AnalyticsRepository repository, {
  Size size = const Size(390, 844),
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
  await tester.pumpAndSettle();
}

Future<void> _selectSection(WidgetTester tester, String label) async {
  final selector = find.byKey(const ValueKey('analytics-section-selector'));
  await tester.drag(selector, const Offset(-600, 0));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

class _FakeV2Repository implements AnalyticsRepository {
  _FakeV2Repository({this.empty = false});
  final bool empty;
  int membershipCalls = 0;
  int revenueCalls = 0;
  AnalyticsPeriod? lastPeriod;

  @override
  Future<AnalyticsOverview> loadOverview(AnalyticsPeriod period) async =>
      _overview;
  @override
  Future<AttendanceAnalytics> loadAttendance(AnalyticsPeriod period) async =>
      _attendance;
  @override
  Future<MembershipAnalytics> loadMemberships(AnalyticsPeriod period) async {
    membershipCalls++;
    lastPeriod = period;
    return empty ? _emptyMemberships : _memberships;
  }

  @override
  Future<RevenueAnalytics> loadRevenue(AnalyticsPeriod period) async {
    revenueCalls++;
    lastPeriod = period;
    return empty ? _emptyRevenue : _revenue;
  }
}

final _overview = AnalyticsOverview(
  timezone: 'Europe/Madrid',
  from: DateTime(2026, 8, 1),
  toExclusive: DateTime(2026, 9, 1),
  current: const AnalyticsMetricSet(
    activeMembers: 1,
    newMembers: 1,
    deliveredClasses: 1,
    bookings: 1,
    attendances: 1,
    noShows: 0,
    globalOccupancy: 50,
    averageClassOccupancy: 50,
  ),
  previous: const AnalyticsMetricSet(
    activeMembers: 1,
    newMembers: 0,
    deliveredClasses: 0,
    bookings: 0,
    attendances: 0,
    noShows: 0,
    globalOccupancy: null,
    averageClassOccupancy: null,
  ),
);
const _attendance = AttendanceAnalytics(
  trend: [],
  programs: [],
  weekdays: [],
  hours: [],
  mostOccupiedClasses: [],
  leastOccupiedClasses: [],
);
const _memberships = MembershipAnalytics(
  snapshot: MembershipSnapshot(
    active: 7,
    activePacks: 5,
    activeUnlimited: 2,
    scheduled: 1,
    exhausted: 2,
    expired: 3,
    cancelled: 1,
    replaced: 1,
  ),
  created: 4,
  previousCreated: 2,
  credits: MembershipCreditAnalytics(
    purchasedGranted: 20,
    assignedGranted: 5,
    consumed: 9,
    refunded: 2,
    netConsumed: 7,
    currentRemaining: 11,
    expiredUnused: 3,
    unclassifiedLogs: 0,
  ),
  plans: [
    MembershipPlanAnalytics(
      id: 'p1',
      name: 'Pack 5',
      membershipsCreated: 3,
      activeNow: 2,
      paidSales: 2,
      directAssignments: 1,
    ),
  ],
);
const _emptyMemberships = MembershipAnalytics(
  snapshot: MembershipSnapshot(
    active: 0,
    activePacks: 0,
    activeUnlimited: 0,
    scheduled: 0,
    exhausted: 0,
    expired: 0,
    cancelled: 0,
    replaced: 0,
  ),
  created: 0,
  previousCreated: 0,
  credits: MembershipCreditAnalytics(
    purchasedGranted: 0,
    assignedGranted: 0,
    consumed: 0,
    refunded: 0,
    netConsumed: 0,
    currentRemaining: 0,
    expiredUnused: 0,
    unclassifiedLogs: 0,
  ),
  plans: [],
);
final _revenue = RevenueAnalytics(
  currencies: [
    RevenueCurrencyAnalytics(
      currency: 'EUR',
      totalMinor: 7000,
      paymentCount: 2,
      averageMinor: 3500,
      previousTotalMinor: 3500,
      previousPaymentCount: 1,
      previousAverageMinor: 3500,
    ),
    RevenueCurrencyAnalytics(
      currency: 'USD',
      totalMinor: 2000,
      paymentCount: 1,
      averageMinor: 2000,
      previousTotalMinor: 0,
      previousPaymentCount: 0,
      previousAverageMinor: null,
    ),
  ],
  methods: [
    RevenueMethodAnalytics(
      currency: 'EUR',
      method: 'card',
      totalMinor: 3500,
      paymentCount: 1,
    ),
    RevenueMethodAnalytics(
      currency: 'EUR',
      method: 'cash',
      totalMinor: 3500,
      paymentCount: 1,
    ),
  ],
  plans: [
    RevenuePlanAnalytics(
      currency: 'EUR',
      id: 'p1',
      name: 'Pack 5',
      revenueMinor: 7000,
      paymentCount: 2,
      averageMinor: 3500,
      revenueShare: 100,
    ),
  ],
  trend: [
    RevenueTrendPoint(
      date: DateTime(2026, 8, 20),
      currency: 'EUR',
      totalMinor: 7000,
      paymentCount: 2,
    ),
    RevenueTrendPoint(
      date: DateTime(2026, 8, 21),
      currency: 'USD',
      totalMinor: 2000,
      paymentCount: 1,
    ),
  ],
  states: RevenueStateCounts(paid: 3, pending: 1, failed: 1, cancelled: 1),
  excluded: RevenueExcludedCounts(
    paidMissingAudit: 0,
    legacyApprovedPending: 1,
    unclassifiedManualMethod: 0,
  ),
);
const _emptyRevenue = RevenueAnalytics(
  currencies: [],
  methods: [],
  plans: [],
  trend: [],
  states: RevenueStateCounts(paid: 0, pending: 0, failed: 0, cancelled: 0),
  excluded: RevenueExcludedCounts(
    paidMissingAudit: 0,
    legacyApprovedPending: 0,
    unclassifiedManualMethod: 0,
  ),
);
