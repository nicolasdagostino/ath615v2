import 'package:ath615v2/features/booking/domain/class_coach.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the minimal list_assignable_class_coaches contract', () {
    final coach = ClassCoachOption.fromRpcRow({
      'coach_id': 'coach-1',
      'coach_name': 'Alex Coach',
    });

    expect(coach?.id, 'coach-1');
    expect(coach?.name, 'Alex Coach');
  });

  test('ignores malformed RPC rows', () {
    expect(ClassCoachOption.fromRpcRow({'coach_id': 'coach-1'}), isNull);
    expect(ClassCoachOption.fromRpcRow({'coach_name': 'Alex'}), isNull);
  });

  test('create and edit payloads carry the selected coach id', () {
    final createPayload = withClassCoach({'title': 'WOD'}, 'coach-1');
    final editPayload = withClassCoach({'capacity': 12}, 'coach-2');

    expect(createPayload['coach_id'], 'coach-1');
    expect(editPayload['coach_id'], 'coach-2');
  });

  test('no Coach is represented by a null coach id', () {
    final payload = withClassCoach({'title': 'WOD'}, null);
    expect(payload, containsPair('coach_id', null));
  });

  test('recurring payload carries the selected coach id', () {
    final params = withRecurringClassCoach({'p_weeks': 8}, 'coach-1');
    expect(params['p_coach_id'], 'coach-1');
  });
}
