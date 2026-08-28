import 'package:ath615v2/features/owner/presentation/screens/owner_screen.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
