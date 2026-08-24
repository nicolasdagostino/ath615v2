import 'package:ath615v2/features/notifications/navigation/notification_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('valid workout date builds structural WOD destination', () {
    final date = parseNotificationDate('2026-08-13');
    expect(date, DateTime(2026, 8, 13));
    expect(wodDestination(date!), '/app?section=wod&date=2026-08-13');
  });

  test('invalid route dates are rejected', () {
    expect(parseNotificationDate('2026-02-31'), isNull);
    expect(parseNotificationDate('13/08/2026'), isNull);
    expect(parseNotificationDate(null), isNull);
  });

  test('only explicit workout notification types route to WOD', () {
    for (final type in workoutNotificationTypes) {
      expect(isWorkoutNotification(type: type, data: const {}), isTrue);
    }
    expect(
      isWorkoutNotification(
        type: 'class_reminder',
        data: const {'workoutId': 'incidental-id'},
      ),
      isFalse,
    );
  });
}
