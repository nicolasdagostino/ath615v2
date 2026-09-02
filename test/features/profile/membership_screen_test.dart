import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_detail_header.dart';
import 'package:ath615v2/features/profile/presentation/screens/membership_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeMemberships implements UserMembershipsDataSource {
  _FakeMemberships({
    this.current = const [],
    this.history = const [],
    this.usage = const {},
  });

  final List<Map<String, dynamic>> current;
  final List<Map<String, dynamic>> history;
  final Map<String, List<Map<String, dynamic>>> usage;
  final List<int> historyOffsets = [];
  final List<String> usageMemberships = [];
  int currentLoads = 0;
  List<Map<String, dynamic>> pending = const [];

  @override
  Future<List<Map<String, dynamic>>> loadCurrentAndScheduled() async {
    currentLoads += 1;
    return current;
  }

  @override
  Future<List<Map<String, dynamic>>> loadHistory({
    required int offset,
    required int limit,
  }) async {
    historyOffsets.add(offset);
    return history.skip(offset).take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> loadPendingRequests() async => pending;

  @override
  Future<List<Map<String, dynamic>>> loadUsage({
    required String membershipId,
    required int offset,
    required int limit,
  }) async {
    usageMemberships.add(membershipId);
    return (usage[membershipId] ?? const []).skip(offset).take(limit).toList();
  }
}

Map<String, dynamic> membership(
  String id,
  String status, {
  String type = 'class_pack',
  int? credits = 5,
  int? remaining = 2,
  String starts = '2026-01-12T10:00:00Z',
}) => {
  'id': id,
  'status': status,
  'is_active': status == 'active' || status == 'scheduled',
  'starts_at': starts,
  'expires_at': '2026-02-12T10:00:00Z',
  'created_at': starts,
  'credits_remaining': type == 'unlimited' ? null : remaining,
  'membership_plans': {
    'name': type == 'unlimited' ? 'Unlimited' : '5 Classes',
    'plan_type': type,
    'credits': type == 'unlimited' ? null : credits,
  },
};

Future<void> pumpMemberships(
  WidgetTester tester,
  UserMembershipsDataSource source, {
  ThemeMode mode = ThemeMode.light,
}) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: MembershipScreen(dataSource: source),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });

  testWidgets('separates current, scheduled and history by year at 320px', (
    tester,
  ) async {
    final source = _FakeMemberships(
      current: [
        membership('active', 'active'),
        membership(
          'scheduled',
          'scheduled',
          type: 'unlimited',
          starts: '2026-10-01T10:00:00Z',
        ),
      ],
      history: [
        membership('old-2026', 'expired'),
        membership('old-2025', 'exhausted', starts: '2025-03-01T10:00:00Z'),
      ],
    );
    source.pending = [
      {
        'id': 'request-1',
        'status': 'pending',
        'payment_method': 'cash',
        'membership_plans': {
          'name': 'Pending Pack',
          'plan_type': 'class_pack',
          'credits': 5,
        },
      },
    ];
    await pumpMemberships(tester, source);

    expect(find.byType(AppDetailHeader), findsOne);
    final back = tester.widget<Icon>(
      find.descendant(
        of: find.byType(AppDetailHeader),
        matching: find.byIcon(Icons.arrow_back_ios_new_rounded),
      ),
    );
    expect(
      back.color,
      AppColors.accent,
    );
    expect(find.byKey(const ValueKey('membership-current-active')), findsOne);
    expect(find.text('UPCOMING'), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('membership-request-request-1')),
      150,
    );
    expect(find.text('REQUESTED'), findsOne);
    expect(find.text('Request pending · In-person payment'), findsOne);
    expect(
      find.byKey(const ValueKey('membership-request-request-1')),
      findsOne,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('membership-history-year-2025')),
      200,
    );
    expect(
      find.byKey(const ValueKey('membership-history-year-2026')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('membership-history-year-2025')),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('memberships header owns the notched top safe area', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(() => tester.view.padding = FakeViewPadding.zero);
    await pumpMemberships(tester, _FakeMemberships());

    final header = find.byType(AppDetailHeader);
    expect(tester.getTopLeft(header).dy, 0);
    expect(
      tester.getTopLeft(find.byIcon(Icons.arrow_back_ios_new_rounded)).dy,
      greaterThanOrEqualTo(47),
    );
  });

  testWidgets('empty current state is clean in light and dark', (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await pumpMemberships(tester, _FakeMemberships(), mode: mode);
      expect(find.byKey(const ValueKey('memberships-no-current')), findsOne);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('detail is a high sheet and loads only its membership usage', (
    tester,
  ) async {
    final source = _FakeMemberships(
      current: [membership('pack-5', 'active')],
      usage: {
        'pack-5': [
          {
            'id': 'booking-1',
            'membership_id': 'pack-5',
            'status': 'attended',
            'classes': {
              'title': 'Class',
              'starts_at': '2026-08-13T18:30:00Z',
              'programs': {'name': 'CrossFit'},
            },
          },
        ],
      },
    );
    await pumpMemberships(tester, source);
    await tester.tap(find.byKey(const ValueKey('membership-current-pack-5')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('membership-detail-sheet'));
    expect(sheet, findsOne);
    expect(tester.getSize(sheet).height, closeTo(720 * .92, 2));
    expect(source.usageMemberships, ['pack-5']);
    expect(find.byKey(const ValueKey('membership-usage-booking-1')), findsOne);
  });

  test('usage excludes refunded cancellation and another membership', () {
    final rows = [
      {'membership_id': 'pack-5', 'status': 'booked'},
      {'membership_id': 'pack-5', 'status': 'attended'},
      {'membership_id': 'pack-5', 'status': 'no_show'},
      {'membership_id': 'pack-5', 'status': 'cancelled'},
      {'membership_id': 'other-pack', 'status': 'attended'},
    ];
    final usage = rows
        .where((row) => isFinalMembershipUsage(row, 'pack-5'))
        .toList();
    expect(usage, hasLength(3));
    expect(usage.map((row) => row['status']), [
      'booked',
      'attended',
      'no_show',
    ]);
  });

  testWidgets('history and detail usage paginate in bounded pages', (
    tester,
  ) async {
    final history = List.generate(
      membershipHistoryPageSize + 1,
      (index) => membership('history-$index', 'expired'),
    );
    final usage = List.generate(
      membershipUsagePageSize + 1,
      (index) => {
        'id': 'booking-$index',
        'membership_id': 'pack',
        'status': 'booked',
        'classes': <String, dynamic>{},
      },
    );
    final source = _FakeMemberships(
      current: [membership('pack', 'active')],
      history: history,
      usage: {'pack': usage},
    );
    await pumpMemberships(tester, source);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('memberships-load-more')),
      300,
    );
    await tester.tap(find.byKey(const ValueKey('memberships-load-more')));
    await tester.pumpAndSettle();
    expect(source.historyOffsets, [0, membershipHistoryPageSize]);

    await tester.drag(
      find.byKey(const ValueKey('memberships-scroll')),
      const Offset(0, 3000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('membership-current-pack')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('membership-usage-load-more')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('membership-usage-load-more')));
    await tester.pumpAndSettle();
    expect(source.usageMemberships, ['pack', 'pack']);
  });

  testWidgets('successful acquisition result refreshes My Memberships', (
    tester,
  ) async {
    final source = _FakeMemberships();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MembershipScreen(dataSource: source),
        ),
        GoRoute(
          path: '/available-memberships/:type',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('complete-membership-request'),
                onPressed: () => context.pop(true),
                child: const Text('Complete'),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(source.currentLoads, 1);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('memberships-get-subscription')),
      200,
    );
    await tester.tap(
      find.byKey(const ValueKey('memberships-get-subscription')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-membership-request')));
    await tester.pumpAndSettle();
    expect(source.currentLoads, 2);
  });

  testWidgets('admin member section reuses current scheduled history detail', (
    tester,
  ) async {
    final source = _FakeMemberships(
      current: [
        membership('current', 'active'),
        membership('next', 'scheduled', type: 'unlimited'),
      ],
      history: [membership('old', 'expired')],
      usage: {'old': const []},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MemberMembershipsSection(
              memberId: 'member-1',
              dataSource: source,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('admin-member-memberships')), findsOne);
    expect(find.text('CURRENT MEMBERSHIP'), findsOne);
    expect(find.text('UPCOMING'), findsOne);
    expect(find.text('HISTORY'), findsOne);

    await tester.tap(find.byKey(const ValueKey('membership-row-old')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('membership-detail-sheet')), findsOne);
    expect(source.usageMemberships, ['old']);
  });
}
