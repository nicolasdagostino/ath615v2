import 'package:ath615v2/features/auth/presentation/screens/auth_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AuthGate only redirects while it still owns the root route', () {
    expect(shouldAuthGateRedirect('/'), isTrue);
    expect(shouldAuthGateRedirect('/membership'), isFalse);
    expect(shouldAuthGateRedirect('/reset-password'), isFalse);
    expect(shouldAuthGateRedirect('/gym-settings'), isFalse);
  });
}
