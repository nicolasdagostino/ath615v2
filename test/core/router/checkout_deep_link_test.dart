import 'package:ath615v2/core/router/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful Checkout return opens memberships', () {
    final destination = checkoutReturnDestination(
      Uri.parse(
        'athletelab://checkout?status=success&session_id=cs_test_example',
      ),
    );

    expect(destination, '/membership?checkout=success');
  });

  test(
    'cancelled Checkout return opens memberships without claiming payment',
    () {
      final destination = checkoutReturnDestination(
        Uri.parse('athletelab://checkout?status=cancel'),
      );

      expect(destination, '/membership?checkout=cancel');
    },
  );

  test('unrelated app links are ignored by the Checkout resolver', () {
    expect(
      checkoutReturnDestination(Uri.parse('athletelab://reset-password')),
      isNull,
    );
  });
}
