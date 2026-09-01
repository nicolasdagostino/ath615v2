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
                'saas_usage': {
                  'plan_code': 'growth',
                  'plan_name': 'GROWTH',
                  'active_athlete_count': 72,
                  'active_member_limit': 100,
                  'remaining_slots': 28,
                },
                'saas_plans': [
                  {
                    'code': 'free',
                    'name': 'FREE',
                    'active_member_limit': 10,
                    'monthly_price_eur': 0,
                  },
                  {
                    'code': 'growth',
                    'name': 'GROWTH',
                    'active_member_limit': 100,
                    'monthly_price_eur': 39,
                  },
                  {
                    'code': 'unlimited',
                    'name': 'UNLIMITED',
                    'active_member_limit': null,
                    'monthly_price_eur': 79,
                  },
                ],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('gym-information-title')), findsOne);
        expect(find.byKey(const ValueKey('secondary-header-back')), findsOne);
        expect(find.byType(AppFormSectionLabel), findsNWidgets(2));
        expect(find.byType(TextField), findsAtLeast(3));
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
        expect(find.byType(AppFormSubmitButton), findsOne);
        expect(find.text(appStrings.saveChanges.toUpperCase()), findsOne);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('gym-saas-plan-card')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const ValueKey('gym-saas-plan-card')), findsOne);
        expect(find.text('GROWTH'), findsOne);
        expect(find.text('72 / 100 active athletes'), findsOne);
        await tester.tap(find.text('View plan'));
        await tester.pumpAndSettle();
        expect(find.text('YOUR PLAN'), findsOne);
        expect(
          find.byKey(const ValueKey('saas-current-plan-detail')),
          findsOne,
        );
        expect(
          find.textContaining('Deactivate at least 62 athletes'),
          findsOne,
        );
        expect(find.byKey(const ValueKey('saas-manage-members')), findsOne);
        expect(find.textContaining('UNLIMITED'), findsOne);
        final currentRequest = tester.widget<TextButton>(
          find.descendant(
            of: find.byKey(const ValueKey('saas-plan-growth')),
            matching: find.byType(TextButton),
          ),
        );
        expect(currentRequest.onPressed, isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('gym-stripe-status')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(appStrings.stripeNotConnected), findsOne);
        expect(find.text(appStrings.connectStripe), findsOne);
        expect(stripeConnectSetupEnabled, isTrue);
        expect(find.text(appStrings.comingSoon), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('SaaS downgrade shortfall and errors remain human', () {
    expect(saasPlanCapacityShortfall(active: 73, limit: 40), 33);
    expect(saasPlanCapacityShortfall(active: 10, limit: 10), 0);
    expect(saasPlanCapacityShortfall(active: 300, limit: null), 0);
    expect(
      saasPlanChangeErrorMessage(Exception('P0001 saas_plan_capacity_too_low')),
      isNot(contains('P0001')),
    );
    expect(
      saasPlanChangeErrorMessage(Exception('PostgrestException unknown_rpc')),
      isNot(anyOf(contains('Postgrest'), contains('unknown_rpc'))),
    );
  });

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

  testWidgets('Connect return refreshes authoritative Stripe status', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GymSettingsScreen(
          connectAction: StripeConnectRouteAction.returnAndRefresh,
          gymLoaderForTesting: () async => _connectedGym,
          statusRefresherForTesting: () async => refreshes++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(refreshes, 1);
    expect(find.byKey(const ValueKey('gym-information-title')), findsOneWidget);
  });

  testWidgets('expired Account Link opens one continuation for same context', (
    tester,
  ) async {
    var continuations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GymSettingsScreen(
          connectAction: StripeConnectRouteAction.refreshOnboarding,
          gymLoaderForTesting: () async => _connectedGym,
          onboardingOpenerForTesting: () async => continuations++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(continuations, 1);
    expect(find.byKey(const ValueKey('gym-information-title')), findsOneWidget);
  });
}

const _connectedGym = <String, dynamic>{
  'id': 'gym-1',
  'business_name': 'ATHLETE 615',
  'phone': '',
  'email': 'gym@example.com',
  'website': 'athlete615.com',
  'address': 'Madrid',
  'logo_url': null,
  'gym_code': null,
  'stripe_account_id': 'acct_test',
  'stripe_onboarding_complete': false,
  'stripe_charges_enabled': false,
  'stripe_payouts_enabled': false,
};
