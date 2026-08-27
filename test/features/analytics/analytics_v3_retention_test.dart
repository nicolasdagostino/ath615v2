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

  testWidgets('Retention chip loads one summary and objective segment counts', (
    tester,
  ) async {
    final repository = _FakeRetentionRepository();
    await _pump(tester, repository);
    await _selectRetention(tester);

    expect(repository.summaryCalls, 1);
    expect(
      find.byKey(const ValueKey('analytics-retention-overview')),
      findsOneWidget,
    );
    expect(find.text('No attendance in 14 days'), findsOneWidget);
    expect(find.text('8 members'), findsWidgets);
    expect(find.text('COHORTS'), findsNothing);
  });

  testWidgets('segment supports selection, visible selection and clear', (
    tester,
  ) async {
    final repository = _FakeRetentionRepository();
    await _pump(tester, repository);
    await _selectRetention(tester);
    await tester.tap(find.text('No attendance in 14 days'));
    await tester.pumpAndSettle();

    expect(repository.segmentCalls, 1);
    expect(find.text('Member One'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('retention-send-communication')),
      findsOneWidget,
    );

    await tester.tap(find.text('Select visible'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('member row reuses administrative Member Detail callback', (
    tester,
  ) async {
    Map<String, dynamic>? opened;
    await _pump(
      tester,
      _FakeRetentionRepository(),
      onOpenMember: (member) => opened = member,
    );
    await _selectRetention(tester);
    await tester.tap(find.text('No attendance in 14 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Member One'));
    expect(opened?['id'], 'user-1');
    expect(opened?['role'], 'athlete');
  });

  testWidgets('pagination appends only the requested next page', (
    tester,
  ) async {
    final repository = _FakeRetentionRepository(hasMore: true);
    await _pump(tester, repository);
    await _selectRetention(tester);
    await tester.tap(find.text('No attendance in 14 days'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(repository.offsets, [0, 2]);
    expect(find.text('Member Three'), findsOneWidget);
  });

  testWidgets('manual communication confirms and sends selected IDs', (
    tester,
  ) async {
    final repository = _FakeRetentionRepository();
    await _pump(tester, repository);
    await _selectRetention(tester);
    await tester.tap(find.text('No attendance in 14 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select visible'));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('retention-send-communication')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('retention-communication-title')),
      'We miss you',
    );
    await tester.enterText(
      find.byKey(const ValueKey('retention-communication-body')),
      'Come train this week.',
    );
    await tester.tap(find.text('SEND COMMUNICATION').last);
    await tester.pumpAndSettle();
    expect(find.text('Send communication?'), findsOneWidget);
    await tester.tap(find.text('Send communication').last);
    await tester.pumpAndSettle();

    expect(repository.sentRecipientIds, ['user-1', 'user-2']);
    expect(find.text('Communication sent to 2 members.'), findsOneWidget);
  });

  testWidgets('empty retention segment is stable at 320 px in Spanish', (
    tester,
  ) async {
    await localeController.setLanguage('es');
    await _pump(
      tester,
      _FakeRetentionRepository(empty: true),
      size: const Size(320, 700),
    );
    await _selectRetention(tester, label: 'RETENCIÓN');
    await tester.ensureVisible(find.text('Plan próximo a vencer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan próximo a vencer'));
    await tester.pumpAndSettle();
    expect(find.text('No hay membresías próximas a vencer.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AnalyticsRepository repository, {
  Size size = const Size(390, 844),
  ValueChanged<Map<String, dynamic>>? onOpenMember,
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
            children: [
              AnalyticsView(repository: repository, onOpenMember: onOpenMember),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectRetention(
  WidgetTester tester, {
  String label = 'RETENTION',
}) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

class _FakeRetentionRepository implements AnalyticsRepository {
  _FakeRetentionRepository({this.empty = false, this.hasMore = false});
  final bool empty;
  final bool hasMore;
  int summaryCalls = 0;
  int segmentCalls = 0;
  final List<int> offsets = [];
  List<String>? sentRecipientIds;

  @override
  Future<RetentionSummary> loadRetentionSummary() async {
    summaryCalls++;
    return RetentionSummary(
      timezone: 'Europe/Madrid',
      counts: {
        for (final segment in RetentionSegment.values)
          segment: segment == RetentionSegment.noAttendance14 ? 8 : 2,
      },
    );
  }

  @override
  Future<RetentionPage> loadRetentionSegment(
    RetentionSegment segment, {
    required int limit,
    required int offset,
  }) async {
    segmentCalls++;
    offsets.add(offset);
    if (empty) {
      return RetentionPage(
        segment: segment,
        totalCount: 0,
        limit: limit,
        offset: offset,
        items: const [],
      );
    }
    if (offset > 0) {
      return RetentionPage(
        segment: segment,
        totalCount: 3,
        limit: limit,
        offset: offset,
        items: [_member('user-3', 'Member Three')],
      );
    }
    return RetentionPage(
      segment: segment,
      totalCount: hasMore ? 3 : 2,
      limit: limit,
      offset: 0,
      items: [_member('user-1', 'Member One'), _member('user-2', 'Member Two')],
    );
  }

  @override
  Future<RetentionCommunicationResult> sendRetentionCommunication({
    required List<String> recipientIds,
    required String title,
    required String body,
  }) async {
    sentRecipientIds = recipientIds;
    return RetentionCommunicationResult(
      count: recipientIds.length,
      communicationId: 'communication-1',
    );
  }

  @override
  Future<AnalyticsOverview> loadOverview(AnalyticsPeriod period) async =>
      _overview;
  @override
  Future<AttendanceAnalytics> loadAttendance(AnalyticsPeriod period) =>
      throw UnimplementedError();
  @override
  Future<MembershipAnalytics> loadMemberships(AnalyticsPeriod period) =>
      throw UnimplementedError();
  @override
  Future<RevenueAnalytics> loadRevenue(AnalyticsPeriod period) =>
      throw UnimplementedError();
}

RetentionMember _member(String id, String name) => RetentionMember(
  userId: id,
  name: name,
  avatarUrl: null,
  lastAttendedAt: DateTime.now().subtract(const Duration(days: 16)),
  attendancesCount: 4,
  usableMembership: true,
  membershipPlanName: 'Pack 10',
  membershipPlanType: 'class_pack',
  creditsRemaining: 4,
  membershipEndsAt: DateTime.now().add(const Duration(days: 10)),
  hasFutureBooking: id == 'user-1',
  futureBookingAt: id == 'user-1'
      ? DateTime.now().add(const Duration(days: 2))
      : null,
  noShowCount30d: 2,
);

final _overview = AnalyticsOverview(
  timezone: 'Europe/Madrid',
  from: DateTime(2026, 8, 1),
  toExclusive: DateTime(2026, 9, 1),
  current: const AnalyticsMetricSet(
    activeMembers: 1,
    newMembers: 0,
    deliveredClasses: 0,
    bookings: 0,
    attendances: 0,
    noShows: 0,
    globalOccupancy: null,
    averageClassOccupancy: null,
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
