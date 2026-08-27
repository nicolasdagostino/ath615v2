import 'package:ath615v2/features/owner/presentation/screens/owner_screen.dart';
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
    });
    expect(gym.name, 'CrossFit QA');
    expect(gym.count('active_member_count'), 42);
    expect(gym.count('admin_count'), 2);
    expect(gym.count('coach_count'), 4);
    expect(gym.count('athlete_count'), 36);
    expect(gym.count('active_membership_count'), 18);
  });
}
