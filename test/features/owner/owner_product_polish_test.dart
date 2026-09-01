import 'package:ath615v2/features/owner/presentation/screens/owner_screen.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ath615v2/core/theme/app_theme.dart';

void main() {
  test('owner gym summary exposes aggregate counts and Connect state', () {
    final gym = OwnerGymSummary({
      'gym_id': 'gym-a',
      'gym_name': 'CrossFit QA',
      'active_member_count': 42,
      'admin_count': 2,
      'coach_count': 4,
      'athlete_count': 36,
      'active_membership_count': 18,
      'stripe_account_id': 'acct_test',
      'stripe_onboarding_complete': true,
      'stripe_charges_enabled': true,
      'lifecycle_status': 'suspended',
      'created_at': '2026-08-01T10:00:00Z',
      'last_activity_at': '2026-08-27T18:30:00Z',
      'saas_plan_name': 'STARTER',
      'saas_active_member_limit': 40,
      'saas_active_athlete_count': 36,
      'saas_limit_reached': false,
    });
    expect(gym.name, 'CrossFit QA');
    expect(gym.count('active_member_count'), 42);
    expect(gym.count('admin_count'), 2);
    expect(gym.count('coach_count'), 4);
    expect(gym.count('athlete_count'), 36);
    expect(gym.count('active_membership_count'), 18);
    expect(gym.status, 'suspended');
    expect(gym.createdAt, isNotNull);
    expect(gym.lastActivityAt, isNotNull);
    expect(gym.saasPlanName, 'STARTER');
    expect(gym.saasUsageLabel, contains('36 / 40'));
  });

  test('owner SaaS usage supports unlimited and reached states', () {
    final unlimited = OwnerGymSummary({
      'saas_plan_name': 'UNLIMITED',
      'saas_active_athlete_count': 87,
    });
    final reached = OwnerGymSummary({
      'saas_plan_name': 'FREE',
      'saas_active_member_limit': 10,
      'saas_active_athlete_count': 10,
      'saas_limit_reached': true,
    });
    expect(unlimited.saasUsageLabel, contains('Unlimited'));
    expect(reached.saasUsageLabel, contains('Limit reached'));
    final over = OwnerGymSummary({
      'saas_plan_name': 'STARTER',
      'saas_active_member_limit': 40,
      'saas_active_athlete_count': 47,
      'saas_over_limit': true,
    });
    expect(over.saasUsageLabel, contains('Over limit'));
  });

  test('gym card opens Owner detail and admin entry remains explicit', () {
    final source = File(
      'lib/features/owner/presentation/screens/owner_screen.dart',
    ).readAsStringSync();
    expect(source, contains("context.push('/owner/gym/\${gym.id}')"));
    expect(source, contains("appStrings.pick('ENTER AS ADMIN'"));
    expect(source, contains("'select_owner_effective_gym'"));
    expect(
      source.indexOf("'select_owner_effective_gym'"),
      greaterThan(source.indexOf('Future<void> _enterAdmin()')),
    );
  });

  testWidgets('Platform Owner request card exposes commercial review actions', (
    tester,
  ) async {
    var approved = false;
    var rejected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OwnerPlanRequestCard(
            request: const {
              'id': 'request-1',
              'gym_name': 'ATHLETE 615',
              'current_plan_name': 'STARTER',
              'requested_plan_name': 'GROWTH',
              'active_athlete_count': 21,
              'current_price_eur': 19,
              'requested_price_eur': 39,
            },
            onApprove: () => approved = true,
            onReject: () => rejected = true,
          ),
        ),
      ),
    );
    expect(find.text('STARTER → GROWTH'), findsOne);
    expect(find.textContaining('€19 → €39'), findsOne);
    await tester.tap(find.text('APPROVE'));
    await tester.tap(find.text('REJECT'));
    expect(approved, isTrue);
    expect(rejected, isTrue);
  });
}
