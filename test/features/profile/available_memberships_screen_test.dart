import 'dart:async';
import 'dart:io';

import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_centered_loading_indicator.dart';
import 'package:ath615v2/core/widgets/app_detail_header.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:ath615v2/features/profile/presentation/screens/available_memberships_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAvailableService implements AvailableMembershipsService {
  _FakeAvailableService({
    required this.plans,
    this.failRequest = false,
    this.requestError,
    this.failLoad = false,
    this.loadCompleter,
    this.gymDocuments = const [],
    this.legalDocuments = const [
      {
        'id': 'terms-v1',
        'type': 'terms',
        'version': '2026-08-25',
        'url': 'https://athlete615.com/terms-and-conditions',
        'required': true,
      },
      {
        'id': 'privacy-v1',
        'type': 'privacy',
        'version': '2026-08-25',
        'url': 'https://athlete615.com/privacy-policy',
        'required': false,
      },
    ],
  });

  final List<Map<String, dynamic>> plans;
  final bool failRequest;
  final Object? requestError;
  final bool failLoad;
  final Completer<List<Map<String, dynamic>>>? loadCompleter;
  final List<Map<String, dynamic>> gymDocuments;
  final List<Map<String, dynamic>> legalDocuments;
  final List<String> loadedTypes = [];
  final List<String> requestedPlans = [];
  final List<String> paidPlans = [];
  final List<List<String>> acceptedDocuments = [];
  final List<List<String>> acceptedGymDocuments = [];

  @override
  Future<MembershipCheckoutContext> loadCheckoutContext(
    Map<String, dynamic> plan,
  ) async => MembershipCheckoutContext(
    gym: const {'name': 'ATHLETE 615', 'businessName': 'ATHLETE 615 SL'},
    documents: legalDocuments,
    gymDocuments: gymDocuments,
  );

  @override
  Future<List<Map<String, dynamic>>> loadPlans(String type) async {
    loadedTypes.add(type);
    if (failLoad) throw StateError('column description does not exist');
    if (loadCompleter != null) return loadCompleter!.future;
    return plans;
  }

  @override
  Future<void> payByCard(
    Map<String, dynamic> plan,
    List<String> documentIds,
    List<String> gymDocumentVersionIds,
  ) async {
    paidPlans.add(plan['id'].toString());
    acceptedGymDocuments.add(gymDocumentVersionIds);
  }

  @override
  Future<MembershipRequestResult> requestPlan(
    Map<String, dynamic> plan,
    List<String> documentIds,
    List<String> gymDocumentVersionIds,
  ) async {
    requestedPlans.add(plan['id'].toString());
    acceptedDocuments.add(documentIds);
    acceptedGymDocuments.add(gymDocumentVersionIds);
    if (requestError case final error?) throw error;
    if (failRequest) throw StateError('request failed');
    return MembershipRequestResult.sent;
  }
}

Map<String, dynamic> plan({required bool unlimited}) => {
  'id': unlimited ? 'unlimited' : 'dropin',
  'name': unlimited ? 'Unlimited Performance With A Long Name' : 'Single Class',
  'plan_type': unlimited ? 'unlimited' : 'class_pack',
  'credits': unlimited ? null : 1,
  'duration_days': unlimited ? 30 : 7,
  'price': unlimited ? 89.90 : 15,
  'currency': 'EUR',
};

Future<void> _pumpFlow(
  WidgetTester tester, {
  required String type,
  required _FakeAvailableService service,
  ThemeMode mode = ThemeMode.light,
  bool settle = true,
  Future<void> Function(BuildContext context)? reviewDocuments,
}) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: AvailableMembershipsScreen(
        key: ValueKey(service),
        type: type,
        service: service,
        reviewDocuments: reviewDocuments,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('subscription uses real plan data at 320px ${mode.name}', (
      tester,
    ) async {
      final service = _FakeAvailableService(plans: [plan(unlimited: true)]);
      await _pumpFlow(
        tester,
        type: 'subscription',
        service: service,
        mode: mode,
      );
      expect(service.loadedTypes, ['subscription']);
      expect(find.byType(AppDetailHeader), findsOne);
      final back = tester.widget<Icon>(
        find.descendant(
          of: find.byType(AppDetailHeader),
          matching: find.byIcon(Icons.arrow_back_ios_new_rounded),
        ),
      );
      expect(back.color, AppColors.accent);
      expect(find.textContaining('UNLIMITED PERFORMANCE'), findsOne);
      expect(find.text('Unlimited access'), findsOne);
      expect(find.text('30 days'), findsOne);
      expect(find.text('€89.9'), findsOne);
      expect(tester.takeException(), isNull);
    });
  }

  for (final type in ['subscription', 'dropin']) {
    testWidgets('$type header owns the notched top safe area', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 47);
      addTearDown(() => tester.view.padding = FakeViewPadding.zero);
      await _pumpFlow(
        tester,
        type: type,
        service: _FakeAvailableService(
          plans: [plan(unlimited: type == 'subscription')],
        ),
      );

      final header = find.byType(AppDetailHeader);
      expect(tester.getTopLeft(header).dy, 0);
      expect(
        tester.getTopLeft(find.byIcon(Icons.arrow_back_ios_new_rounded)).dy,
        greaterThanOrEqualTo(47),
      );
    });
  }

  testWidgets('drop-in checkout requires consent and requests in person', (
    tester,
  ) async {
    final service = _FakeAvailableService(plans: [plan(unlimited: false)]);
    await _pumpFlow(tester, type: 'dropin', service: service);
    expect(service.loadedTypes, ['dropin']);
    expect(find.text('1 class credit'), findsOne);

    await tester.tap(find.byKey(const ValueKey('available-plan-dropin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('membership-request-sheet')), findsOne);
    await tester.scrollUntilVisible(
      find.byType(AppFormSubmitButton),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('membership-request-sheet')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      tester
          .widget<AppFormSubmitButton>(find.byType(AppFormSubmitButton))
          .enabled,
      isFalse,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('checkout-document-terms')),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('membership-request-sheet')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('checkout-document-toggle-terms')),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byType(AppFormSubmitButton),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('membership-request-sheet')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byType(AppFormSubmitButton), findsOne);
    expect(
      tester
          .widget<AppFormSubmitButton>(find.byType(AppFormSubmitButton))
          .enabled,
      isTrue,
    );
    await tester.tap(find.text('REQUEST MEMBERSHIP'));
    await tester.pumpAndSettle();
    expect(service.requestedPlans, ['dropin']);
    expect(service.acceptedDocuments, [
      ['terms-v1'],
    ]);
  });

  testWidgets('request errors remain in the shared sheet', (tester) async {
    final service = _FakeAvailableService(
      plans: [plan(unlimited: true)],
      failRequest: true,
    );
    await _pumpFlow(tester, type: 'subscription', service: service);
    await tester.tap(find.byKey(const ValueKey('available-plan-unlimited')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('checkout-document-terms')),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('membership-request-sheet')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('checkout-document-toggle-terms')),
    );
    await tester.scrollUntilVisible(
      find.byType(AppFormSubmitButton),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('membership-request-sheet')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('REQUEST MEMBERSHIP'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('membership-request-sheet')), findsOne);
    expect(
      find.text('We could not complete the request. Try again.'),
      findsOne,
    );
    expect(find.textContaining('request failed'), findsNothing);
  });

  testWidgets('required consent is human, actionable, and never leaks SQL', (
    tester,
  ) async {
    var reviews = 0;
    final service = _FakeAvailableService(
      plans: [plan(unlimited: true)],
      requestError: const PostgrestException(
        message: 'required_consent_missing',
        code: 'P0001',
        details: 'Bad Request from create_consented_cash_membership_request',
      ),
    );
    await _pumpFlow(
      tester,
      type: 'subscription',
      service: service,
      reviewDocuments: (_) async => reviews++,
    );
    await tester.tap(find.byKey(const ValueKey('available-plan-unlimited')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('checkout-document-terms')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey('checkout-document-toggle-terms')),
    );
    await tester.scrollUntilVisible(
      find.byType(AppFormSubmitButton),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('REQUEST MEMBERSHIP'));
    await tester.pumpAndSettle();

    expect(find.text('A document needs your acceptance'), findsOneWidget);
    expect(
      find.text(
        'Before requesting this membership, review and accept the documents required by the gym.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('membership-review-documents')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const ValueKey('membership-review-documents')),
      findsOneWidget,
    );
    for (final technicalDetail in [
      'PostgrestException',
      'P0001',
      'Bad Request',
      'create_consented_cash_membership_request',
      'required_consent_missing',
    ]) {
      expect(find.textContaining(technicalDetail), findsNothing);
    }

    await tester.tap(find.byKey(const ValueKey('membership-review-documents')));
    await tester.pumpAndSettle();
    expect(reviews, 1);
    expect(
      find.byKey(const ValueKey('checkout-document-terms')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppFormSubmitButton>(find.byType(AppFormSubmitButton))
          .enabled,
      isFalse,
    );
  });

  testWidgets('documents changed opens Documents V1 and reloads checkout', (
    tester,
  ) async {
    var reviews = 0;
    final service = _FakeAvailableService(
      plans: [plan(unlimited: true)],
      requestError: const PostgrestException(
        message: 'documents_changed',
        code: 'P0001',
        details: 'Bad Request',
      ),
    );
    await _pumpFlow(
      tester,
      type: 'subscription',
      service: service,
      reviewDocuments: (_) async => reviews++,
    );
    await tester.tap(find.byKey(const ValueKey('available-plan-unlimited')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('checkout-document-terms')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey('checkout-document-toggle-terms')),
    );
    await tester.scrollUntilVisible(
      find.byType(AppFormSubmitButton),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('REQUEST MEMBERSHIP'));
    await tester.pumpAndSettle();
    expect(find.text('Documents updated'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('membership-review-documents')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('membership-review-documents')));
    await tester.pumpAndSettle();
    expect(reviews, 1);
    expect(
      tester
          .widget<AppFormSubmitButton>(find.byType(AppFormSubmitButton))
          .enabled,
      isFalse,
    );
  });

  testWidgets(
    'card is selectable but cannot create Checkout while flag is off',
    (tester) async {
      final service = _FakeAvailableService(plans: [plan(unlimited: true)]);
      await _pumpFlow(tester, type: 'subscription', service: service);
      await tester.tap(find.byKey(const ValueKey('available-plan-unlimited')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Card'),
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('membership-request-sheet')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Card'));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('checkout-document-terms')),
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('membership-request-sheet')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('checkout-document-toggle-terms')),
      );
      await tester.scrollUntilVisible(
        find.byType(AppFormSubmitButton),
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('membership-request-sheet')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('CONTINUE WITH STRIPE'), findsOne);
      await tester.tap(find.text('CONTINUE WITH STRIPE'));
      await tester.pumpAndSettle();
      expect(service.requestedPlans, isEmpty);
      expect(service.paidPlans, isEmpty);
    },
  );

  testWidgets('loading, empty and error remain distinct states', (
    tester,
  ) async {
    final completer = Completer<List<Map<String, dynamic>>>();
    await _pumpFlow(
      tester,
      type: 'subscription',
      service: _FakeAvailableService(plans: const [], loadCompleter: completer),
      settle: false,
    );
    expect(find.byType(AppCenteredLoadingIndicator), findsOne);
    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No subscriptions available.'), findsOne);
    expect(
      find.byKey(const ValueKey('available-memberships-retry')),
      findsNothing,
    );

    await _pumpFlow(
      tester,
      type: 'dropin',
      service: _FakeAvailableService(plans: const [], failLoad: true),
    );
    expect(
      find.byKey(const ValueKey('available-memberships-error-message')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('available-memberships-retry')), findsOne);
    expect(find.text('No drop-ins available.'), findsNothing);
  });

  test('plan classification follows the current two-type schema', () {
    final unlimited = plan(unlimited: true);
    final dropin = plan(unlimited: false);
    final pack = {
      ...plan(unlimited: false),
      'id': 'pack-10',
      'name': '10 Classes',
      'credits': 10,
    };
    expect(
      classifyAvailableMembershipPlans([
        unlimited,
        dropin,
        pack,
      ], 'subscription').map((row) => row['id']),
      ['unlimited', 'pack-10'],
    );
    expect(
      classifyAvailableMembershipPlans([
        unlimited,
        dropin,
        pack,
      ], 'dropin').map((row) => row['id']),
      ['dropin'],
    );
  });

  testWidgets('checkout requires current gym document and submits version id', (
    tester,
  ) async {
    final service = _FakeAvailableService(
      plans: [plan(unlimited: false)],
      gymDocuments: const [
        {
          'documentId': 'gym-doc-1',
          'versionId': 'gym-version-2',
          'title': 'Gym waiver',
          'body': 'Current immutable terms',
          'versionNumber': 2,
          'acceptanceMode': 'required',
          'accepted': false,
        },
      ],
      legalDocuments: const [],
    );
    await _pumpFlow(tester, type: 'dropin', service: service);
    await tester.tap(find.text('SINGLE CLASS'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Gym waiver'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Gym waiver'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byType(AppFormSubmitButton),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    final submit = tester.widget<AppFormSubmitButton>(
      find.byType(AppFormSubmitButton),
    );
    expect(submit.enabled, isTrue);
    await tester.tap(find.text('REQUEST MEMBERSHIP'));
    await tester.pumpAndSettle();
    expect(service.acceptedGymDocuments.single, ['gym-version-2']);
  });

  test(
    'Supabase plan select only uses fields documented by current code/schema',
    () {
      expect(availableMembershipPlanColumns, isNot(contains('description')));
      final managePlans = File(
        'lib/features/dashboard/presentation/widgets/manage_plans_sheet.dart',
      ).readAsStringSync();
      for (final field in [
        'id',
        'name',
        'plan_type',
        'credits',
        'price',
        'currency',
        'duration_days',
        'is_active',
        'created_at',
      ]) {
        expect(managePlans, contains(field));
        expect(availableMembershipPlanColumns, contains(field));
      }
      final durationMigration = File(
        'supabase/migrations/20260706234543_add_plan_duration_days.sql',
      ).readAsStringSync();
      expect(
        durationMigration,
        contains('add column if not exists duration_days'),
      );
    },
  );
}
