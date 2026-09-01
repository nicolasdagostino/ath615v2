import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invite and reactivation hide technical SaaS limit details', () {
    final technical = Exception(
      'PostgrestException P0001 gym_member_limit_reached',
    );
    final invite = appStrings.inviteAthleteError(technical);
    final reactivate = appStrings.reactivateMemberError(technical);
    expect(invite, contains('active athlete limit'));
    expect(reactivate, contains('active athlete limit'));
    expect(invite, isNot(contains('P0001')));
    expect(invite, isNot(contains('PostgrestException')));
    expect(invite, isNot(contains('gym_member_limit_reached')));
  });

  test('unknown invite and reactivation errors remain generic', () {
    final technical = Exception('42501 secret_rpc forbidden');
    expect(
      appStrings.inviteAthleteError(technical),
      'Could not invite the athlete.',
    );
    expect(
      appStrings.reactivateMemberError(technical),
      'Could not update the member.',
    );
  });
}
