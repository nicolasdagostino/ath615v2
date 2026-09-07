import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/features/public_access/data/help_center_repository.dart';
import 'package:ath615v2/features/public_access/presentation/screens/other_questions_screen.dart';
import 'package:ath615v2/features/public_access/presentation/screens/plans_billing_screen.dart';
import 'package:ath615v2/features/public_access/presentation/screens/public_help_screen.dart';
import 'package:ath615v2/features/public_access/presentation/screens/technical_support_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeHelpRepo implements HelpCenterRepository {
  SupportRequestInput? support;
  ContactRequestInput? contact;
  bool fail = false;
  @override
  Future<void> submitSupport(SupportRequestInput input) async {
    if (fail) throw Exception();
    support = input;
  }

  @override
  Future<void> submitContact(ContactRequestInput input) async {
    if (fail) throw Exception();
    contact = input;
  }

  @override
  Future<List<Map<String, dynamic>>> getPlans() async => [
    {
      'code': 'free',
      'name': 'FREE',
      'active_member_limit': 10,
      'monthly_price_eur': 0,
    },
    {
      'code': 'unlimited',
      'name': 'UNLIMITED',
      'active_member_limit': null,
      'monthly_price_eur': 79,
    },
  ];
  @override
  Future<Map<String, dynamic>?> getAdminPlan() async => null;
  @override
  Future<Map<String, dynamic>?> getPendingPlanRequest() async => null;
  @override
  Future<void> requestPlan(String code) async {}
  @override
  Future<void> cancelPlanRequest(String id) async {}
}

Future<void> pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(home: child));
  await t.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localeController.setLanguage('en');
  });
  testWidgets('Help exposes four functional localized options', (t) async {
    final router = GoRouter(
      initialLocation: '/help',
      routes: [
        GoRoute(path: '/help', builder: (_, _) => const PublicHelpScreen()),
        GoRoute(
          path: '/request-demo',
          builder: (_, _) => const Scaffold(body: Text('demo')),
        ),
        GoRoute(
          path: '/support',
          builder: (_, _) => const Scaffold(body: Text('support')),
        ),
        GoRoute(
          path: '/plans',
          builder: (_, _) => const Scaffold(body: Text('plans')),
        ),
        GoRoute(
          path: '/contact',
          builder: (_, _) => const Scaffold(body: Text('contact')),
        ),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('help-request-demo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('help-technical-support')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('help-plans-billing')), findsOneWidget);
    expect(find.byKey(const ValueKey('help-other-questions')), findsOneWidget);
  });
  testWidgets('Support validates and submits anonymous request', (t) async {
    final r = FakeHelpRepo();
    await pump(t, TechnicalSupportScreen(repository: r));
    final submitButton = find.descendant(
      of: find.byKey(const ValueKey('support-submit')),
      matching: find.byType(FilledButton),
    );
    t.widget<FilledButton>(submitButton).onPressed!();
    await t.pump();
    expect(find.text('Required field'), findsWidgets);
    await t.enterText(find.byKey(const ValueKey('support-name')), 'Ada');
    await t.enterText(
      find.byKey(const ValueKey('support-email')),
      'ada@example.com',
    );
    await t.enterText(
      find.byKey(const ValueKey('support-description')),
      'Booking failed after confirming',
    );
    await t.ensureVisible(find.byKey(const ValueKey('support-submit')));
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('support-submit')),
        matching: find.byType(FilledButton),
      ),
    );
    await t.pumpAndSettle();
    expect(r.support?.issueType, 'login');
    expect(find.byKey(const ValueKey('request-success')), findsOneWidget);
  });
  testWidgets('Other validates and preserves human error for retry', (t) async {
    final r = FakeHelpRepo()..fail = true;
    await pump(t, OtherQuestionsScreen(repository: r));
    for (final e in {
      'contact-name': 'Ada',
      'contact-email': 'ada@example.com',
      'contact-subject': 'Question',
      'contact-message': 'A sufficiently detailed question',
    }.entries) {
      await t.enterText(find.byKey(ValueKey(e.key)), e.value);
    }
    await t.ensureVisible(find.byKey(const ValueKey('contact-submit')));
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('contact-submit')),
        matching: find.byType(FilledButton),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('contact-error')), findsOneWidget);
    expect(find.text('A sufficiently detailed question'), findsOneWidget);
  });
  testWidgets(
    'Public plans show server catalog, limits, unlimited and demo CTA',
    (t) async {
      await pump(t, PlansBillingScreen(repository: FakeHelpRepo()));
      expect(find.textContaining('FREE'), findsOneWidget);
      expect(find.textContaining('10 active athletes'), findsOneWidget);
      expect(find.textContaining('Unlimited active athletes'), findsOneWidget);
      expect(find.byKey(const ValueKey('plans-request-demo')), findsOneWidget);
      expect(find.textContaining('payment method'), findsNothing);
    },
  );
  testWidgets('new Help Center copy is available in Spanish', (t) async {
    await localeController.setLanguage('es');
    addTearDown(() async => localeController.setLanguage('en'));
    await pump(t, PlansBillingScreen(repository: FakeHelpRepo()));
    expect(find.text('PLANES Y FACTURACIÓN'), findsOneWidget);
    expect(find.textContaining('Atletas activos ilimitados'), findsOneWidget);
  });
}
