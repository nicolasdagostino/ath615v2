import 'dart:io';

import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final language in ['en', 'es']) {
    testWidgets('successful recovery always uses neutral copy in $language', (
      tester,
    ) async {
      await localeController.setLanguage(language);
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            requestReset: (email) async {
              submitted.add(email);
            },
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'nonexistent@test.invalid',
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(submitted, ['nonexistent@test.invalid']);
      final expected = language == 'en'
          ? "If an account exists for that email, you'll receive a password reset link."
          : 'Si existe una cuenta asociada a ese email, recibirás un enlace para restablecer tu contraseña.';
      expect(find.text(expected), findsOneWidget);
      expect(find.text('Password email sent.'), findsNothing);
      expect(find.text('Email de recuperación enviado.'), findsNothing);
    });
  }

  testWidgets('network failure uses safe generic feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ForgotPasswordScreen(
          requestReset: (_) async =>
              throw const SocketException('sensitive service detail'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'synthetic@test.invalid');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(
      find.text(appStrings.resetPasswordError(Exception())),
      findsOneWidget,
    );
    expect(find.textContaining('sensitive service detail'), findsNothing);
    expect(find.text(appStrings.authPasswordEmailSent), findsNothing);
  });

  test('request path has no client-side account existence lookup', () {
    final repository = File(
      'lib/features/auth/data/auth_repository.dart',
    ).readAsStringSync();
    final request = repository
        .split('Future<void> resetPassword(String email)')
        .last
        .split('Future<void> updatePassword')
        .first;
    expect(request, contains('resetPasswordForEmail('));
    for (final lookup in [
      '.from(',
      '.rpc(',
      'getUser(',
      'auth.users',
      'gym_members',
      'profiles',
    ]) {
      expect(request, isNot(contains(lookup)));
      expect(
        File(
          'lib/features/auth/presentation/screens/forgot_password_screen.dart',
        ).readAsStringSync(),
        isNot(contains(lookup)),
      );
    }
    expect(
      appStrings.resetPasswordError(Exception('account_not_found')),
      appStrings.resetPasswordError(const SocketException('offline')),
    );
  });
}
