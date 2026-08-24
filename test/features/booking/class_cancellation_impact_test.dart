import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/features/booking/data/class_cancellation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses the server impact without deriving refund rules in Flutter', () {
    final impact = ClassCancellationImpact.fromJson({
      'classes_count': 4,
      'bookings_count': 7,
      'waitlist_count': 2,
      'credits_to_refund': 5,
    });

    expect(impact.classesCount, 4);
    expect(impact.bookingsCount, 7);
    expect(impact.waitlistCount, 2);
    expect(impact.creditsToRefund, 5);
    expect(impact.hasAffectedMembers, isTrue);
  });

  test('single warning reports bookings, waitlist and real refunds', () {
    final message = appStrings.classCancellationImpact(
      classes: 1,
      bookings: 3,
      waitlist: 2,
      credits: 2,
      future: false,
    );

    expect(message, contains('3 bookings'));
    expect(message, contains('2 people'));
    expect(message, contains('2 credits'));
    expect(message, isNot(contains('future classes')));
  });

  test('recurring warning reports the complete future scope', () {
    final message = appStrings.classCancellationImpact(
      classes: 4,
      bookings: 7,
      waitlist: 2,
      credits: 0,
      future: true,
    );

    expect(message, contains('4 future classes'));
    expect(message, contains('7 bookings'));
    expect(message, isNot(contains('credits will be refunded')));
  });

  test(
    'Spanish confirmation uses the approved cancellation language',
    () async {
      await localeController.setLanguage('es');
      addTearDown(() => localeController.setLanguage('en'));

      expect(appStrings.cancelClassTitle, 'Cancelar clase');
      expect(appStrings.doNotCancelClass, 'No cancelar');
      expect(appStrings.confirmCancelClass, 'Sí, cancelar clase');
      expect(
        appStrings.classCancellationImpact(
          classes: 2,
          bookings: 1,
          waitlist: 1,
          credits: 1,
          future: true,
        ),
        contains('Se devolverá 1 crédito.'),
      );
    },
  );
}
