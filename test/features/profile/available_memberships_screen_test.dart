import 'dart:async';
import 'dart:io';

import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_centered_loading_indicator.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:ath615v2/core/widgets/app_secondary_action_header.dart';
import 'package:ath615v2/features/profile/presentation/screens/available_memberships_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAvailableService implements AvailableMembershipsService {
  _FakeAvailableService({
    required this.plans,
    this.failRequest = false,
    this.failLoad = false,
    this.loadCompleter,
  });

  final List<Map<String, dynamic>> plans;
  final bool failRequest;
  final bool failLoad;
  final Completer<List<Map<String, dynamic>>>? loadCompleter;
  final List<String> loadedTypes = [];
  final List<String> requestedPlans = [];

  @override
  Future<List<Map<String, dynamic>>> loadPlans(String type) async {
    loadedTypes.add(type);
    if (failLoad) throw StateError('column description does not exist');
    if (loadCompleter != null) return loadCompleter!.future;
    return plans;
  }

  @override
  Future<void> payByCard(Map<String, dynamic> plan) async {}

  @override
  Future<MembershipRequestResult> requestPlan(Map<String, dynamic> plan) async {
    requestedPlans.add(plan['id'].toString());
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
      expect(find.byType(AppSecondaryActionHeader), findsOne);
      final back = tester.widget<Icon>(
        find.descendant(
          of: find.byType(AppSecondaryActionHeader),
          matching: find.byIcon(Icons.arrow_back_ios_new_rounded),
        ),
      );
      expect(
        back.color,
        AppColors.textPrimary(
          tester.element(find.byType(AppSecondaryActionHeader)),
        ),
      );
      expect(find.textContaining('UNLIMITED PERFORMANCE'), findsOne);
      expect(find.text('Unlimited access'), findsOne);
      expect(find.text('30 days'), findsOne);
      expect(find.text('€89.9'), findsOne);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('drop-in shares selection sheet and shared submit CTA', (
    tester,
  ) async {
    final service = _FakeAvailableService(plans: [plan(unlimited: false)]);
    await _pumpFlow(tester, type: 'dropin', service: service);
    expect(service.loadedTypes, ['dropin']);
    expect(find.text('1 class credit'), findsOne);

    await tester.tap(find.byKey(const ValueKey('available-plan-dropin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('membership-request-sheet')), findsOne);
    expect(find.byType(AppFormSubmitButton), findsOne);
    expect(find.text('REQUEST DROP-IN'), findsOne);
    await tester.tap(find.text('REQUEST DROP-IN'));
    await tester.pumpAndSettle();
    expect(service.requestedPlans, ['dropin']);
  });

  testWidgets('request errors remain in the shared sheet', (tester) async {
    final service = _FakeAvailableService(
      plans: [plan(unlimited: true)],
      failRequest: true,
    );
    await _pumpFlow(tester, type: 'subscription', service: service);
    await tester.tap(find.byKey(const ValueKey('available-plan-unlimited')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REQUEST SUBSCRIPTION'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('membership-request-sheet')), findsOne);
    expect(find.textContaining('request failed'), findsOne);
  });

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
