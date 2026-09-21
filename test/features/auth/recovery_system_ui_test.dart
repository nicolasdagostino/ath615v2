import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/auth/data/app_auth_coordinator.dart';
import 'package:ath615v2/features/auth/data/password_recovery_controller.dart';
import 'package:ath615v2/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:ath615v2/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedSource implements RecoveryDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final reset in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        '${reset ? 'Reset' : 'Forgot'} password overlay matches ${dark ? 'dark' : 'light'} background and respects insets',
        (tester) async {
          final controller = PasswordRecoveryController(
            coordinator: AppAuthCoordinator(),
            source: _UnusedSource(),
            readMarker: () async => null,
            writeMarker: (_) async {},
          );
          addTearDown(controller.dispose);
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: reset
                  ? ResetPasswordScreen(controller: controller)
                  : ForgotPasswordScreen(requestReset: (_) async {}),
            ),
          );
          await tester.pumpAndSettle();
          final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
          );
          expect(region.value.statusBarColor, Colors.transparent);
          expect(
            region.value.statusBarBrightness,
            dark ? Brightness.dark : Brightness.light,
          );
          expect(
            region.value.statusBarIconBrightness,
            dark ? Brightness.light : Brightness.dark,
          );
          expect(find.byType(SafeArea), findsOneWidget);
          expect(
            tester.getTopLeft(find.byType(SingleChildScrollView)).dy,
            greaterThanOrEqualTo(59),
          );
          tester.view.viewInsets = FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(find.byType(SingleChildScrollView), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
