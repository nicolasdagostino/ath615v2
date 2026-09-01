import 'dart:io';

import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/owner/presentation/screens/owner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _frame(Widget child, {double width = 320}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SizedBox(width: width, child: child),
  ),
);

OwnerGymSummary _gym({bool unlimited = false}) => OwnerGymSummary({
  'gym_id': 'gym-v2',
  'gym_name': 'ATHLETE 615 Customer With A Long Name',
  'lifecycle_status': 'active',
  'saas_plan_name': unlimited ? 'UNLIMITED' : 'STARTER',
  'saas_monthly_price_eur': unlimited ? 79 : 19,
  'saas_active_member_limit': unlimited ? null : 40,
  'saas_active_athlete_count': 22,
  'saas_remaining_slots': unlimited ? null : 18,
  'capacity_percent': unlimited ? null : 55,
  'admin_count': 2,
  'coach_count': 3,
  'inactive_athlete_count': 4,
  'active_membership_count': 18,
  'class_count': 32,
  'booking_count': 144,
  'database_record_count': 12430,
  'database_record_share_percent': 42.5,
  'stripe_account_id': 'acct_test',
  'stripe_onboarding_complete': true,
  'stripe_charges_enabled': true,
  'pending_plan_request': {
    'id': 'request-v2',
    'current_plan_name': 'STARTER',
    'requested_plan_name': 'GROWTH',
  },
});

void main() {
  testWidgets('Owner dashboard KPIs and customer card fit narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        ListView(
          children: [
            const OwnerDashboardKpis(
              summary: {
                'active_gym_count': 3,
                'active_athlete_count': 82,
                'pending_plan_request_count': 1,
                'suspended_gym_count': 1,
              },
            ),
            OwnerAttentionPanel(gyms: [_gym()]),
            OwnerGymCustomerCard(gym: _gym(), onTap: () {}, onInvite: () {}),
          ],
        ),
      ),
    );
    expect(find.text('82'), findsOne);
    expect(find.text('22 / 40 athletes'), findsOne);
    expect(find.text('55% capacity'), findsOne);
    expect(find.text('Plan change pending'), findsOne);
    expect(find.byKey(const ValueKey('owner-attention-panel')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gym CRM renders multiple admins and only available actions', (
    tester,
  ) async {
    final calls = <String>[];
    final emails = <String>[];
    await tester.pumpWidget(
      _frame(
        SingleChildScrollView(
          child: OwnerGymContactSection(
            detail: const {
              'contact': {
                'phone': '+34111',
                'email': null,
                'website': 'https://gym.invalid',
                'address': 'Main street',
              },
              'admins': [
                {
                  'full_name': 'Admin One',
                  'email': 'one@test.invalid',
                  'phone': '+34222',
                },
                {'full_name': 'Admin Two', 'email': null, 'phone': null},
              ],
            },
            onCall: calls.add,
            onEmail: emails.add,
          ),
        ),
      ),
    );
    expect(find.text('Admin One'), findsOne);
    expect(find.text('Admin Two'), findsOne);
    expect(find.text('https://gym.invalid'), findsOne);
    expect(find.text('CALL'), findsNWidgets(2));
    expect(find.text('EMAIL'), findsOne);
    await tester.tap(find.text('EMAIL'));
    expect(emails, ['one@test.invalid']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gym CRM handles missing contact data', (tester) async {
    await tester.pumpWidget(
      _frame(
        OwnerGymContactSection(
          detail: const {'contact': {}, 'admins': []},
          onCall: (_) {},
          onEmail: (_) {},
        ),
      ),
    );
    expect(
      find.text('No active administrator contact is available.'),
      findsOne,
    );
    expect(find.text('CALL'), findsNothing);
    expect(find.text('EMAIL'), findsNothing);
  });

  testWidgets('Plan, operational and neutral data metrics render', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        ListView(
          children: [
            OwnerGymCrmHeader(gym: _gym()),
            OwnerGymPlanSection(gym: _gym()),
            OwnerGymOperationalSection(gym: _gym()),
            OwnerGymDataSection(gym: _gym()),
            OwnerGymPlanSection(gym: _gym(unlimited: true)),
          ],
        ),
      ),
    );
    expect(find.text('18 slots available'), findsOne);
    expect(find.text('4 inactive athletes'), findsOne);
    expect(find.text('144 bookings'), findsOne);
    await tester.scrollUntilVisible(
      find.text('12430 tenant data records'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('12430 tenant data records'), findsOne);
    expect(find.textContaining('42.5%'), findsOne);
    await tester.scrollUntilVisible(
      find.text('No member limit'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No member limit'), findsOne);
    expect(tester.takeException(), isNull);
  });

  test('Owner uses one overview RPC and one detail RPC without N+1', () {
    final source = File(
      'lib/features/owner/presentation/screens/owner_screen.dart',
    ).readAsStringSync();
    expect(source, contains("rpc('get_platform_owner_dashboard_v2')"));
    expect(source, contains("'get_platform_gym_crm_v2'"));
    expect(source, isNot(contains("rpc('list_owner_gym_overview')")));
    expect(
      source.substring(
        source.indexOf('class _OwnerGymDetailScreenState'),
        source.indexOf('Future<void> _reviewPending'),
      ),
      isNot(contains("from('profiles')")),
    );
    expect(source, contains("appStrings.pick('ENTER AS ADMIN'"));
    expect(source, contains("appStrings.pick('ADMINISTRATION'"));
  });
}
