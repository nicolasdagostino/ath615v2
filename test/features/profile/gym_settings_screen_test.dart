import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:ath615v2/features/profile/presentation/screens/gym_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'Gym Information uses shared form system at 320px ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            home: GymSettingsScreen(
              gymLoaderForTesting: () async => {
                'id': 'gym-1',
                'business_name': 'ATHLETE 615',
                'phone': '+34 600 000 000',
                'email': 'gym@example.com',
                'website': 'athlete615.com',
                'address': 'Madrid',
                'logo_url': null,
                'gym_code': null,
                'stripe_account_id': null,
                'stripe_onboarding_complete': false,
                'stripe_charges_enabled': false,
                'stripe_payouts_enabled': false,
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('gym-information-title')), findsOne);
        expect(find.byKey(const ValueKey('secondary-header-back')), findsOne);
        expect(find.byType(AppFormSectionLabel), findsNWidgets(2));
        expect(find.byType(TextField), findsNWidgets(5));
        expect(find.byType(AppFormSubmitButton), findsOne);
        expect(find.byIcon(Icons.image_outlined), findsOne);
        final field = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('gym-business-field')),
            matching: find.byType(TextField),
          ),
        );
        expect(
          field.style,
          appFormValueStyle(
            tester.element(find.byKey(const ValueKey('gym-business-field'))),
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('gym-information-save')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(appStrings.saveChanges.toUpperCase()), findsOne);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('gym-stripe-status')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(appStrings.stripeNotConnected), findsOne);
        expect(find.text(appStrings.comingSoon), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'Stripe status reflects real Connect fields without enabling payments',
    () {
      expect(
        gymStripeConnectState(
          accountId: null,
          onboardingComplete: false,
          chargesEnabled: false,
          payoutsEnabled: false,
        ),
        GymStripeConnectState.disconnected,
      );
      expect(
        gymStripeConnectState(
          accountId: 'acct_test',
          onboardingComplete: false,
          chargesEnabled: false,
          payoutsEnabled: false,
        ),
        GymStripeConnectState.setupPending,
      );
      expect(
        gymStripeConnectState(
          accountId: 'acct_test',
          onboardingComplete: true,
          chargesEnabled: false,
          payoutsEnabled: true,
        ),
        GymStripeConnectState.chargesDisabled,
      );
      expect(
        gymStripeConnectState(
          accountId: 'acct_test',
          onboardingComplete: true,
          chargesEnabled: true,
          payoutsEnabled: true,
        ),
        GymStripeConnectState.paymentsEnabled,
      );
    },
  );
}
