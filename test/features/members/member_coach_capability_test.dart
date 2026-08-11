import 'package:ath615v2/features/members/domain/member_coach_capability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('memberHasCoachCapability', () {
    test('supports athlete plus Coach capability', () {
      expect(
        memberHasCoachCapability({'role': 'athlete', 'is_coach': true}),
        isTrue,
      );
    });

    test('supports admin plus Coach capability', () {
      expect(
        memberHasCoachCapability({'role': 'admin', 'is_coach': true}),
        isTrue,
      );
    });

    test('preserves legacy Coach role compatibility', () {
      expect(
        memberHasCoachCapability({'role': 'coach', 'is_coach': false}),
        isTrue,
      );
    });
  });

  test('changing Coach capability does not change operational role', () {
    final member = memberWithCoachCapability({
      'role': 'admin',
      'is_coach': false,
    }, true);

    expect(member['role'], 'admin');
    expect(member['is_coach'], isTrue);
  });

  test('changing role does not remove Coach capability', () {
    final member = memberWithRole({
      'role': 'admin',
      'is_coach': true,
    }, 'athlete');

    expect(member['role'], 'athlete');
    expect(member['is_coach'], isTrue);
    expect(memberHasCoachCapability(member), isTrue);
  });
}
