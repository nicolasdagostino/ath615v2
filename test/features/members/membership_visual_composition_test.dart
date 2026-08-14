import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:ath615v2/features/dashboard/presentation/widgets/manage_plans_sheet.dart';
import 'package:ath615v2/features/members/presentation/widgets/membership_plan_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('membership tab composes at 360 px without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: buildMembershipTabCompositionForTest(),
      ),
    );

    expect(find.byKey(const ValueKey('membership-overview')), findsOneWidget);
    expect(find.text('MEMBERSHIP'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan rows show class pack, unlimited and both statuses', (
    tester,
  ) async {
    var menuOpened = false;
    var toggled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              MembershipPlanRow(
                plan: const {
                  'name': 'Beach',
                  'plan_type': 'class_pack',
                  'credits': 8,
                  'duration_days': 30,
                  'price': 35,
                  'currency': 'EUR',
                  'is_active': true,
                },
                onOpenActions: () => menuOpened = true,
                onToggleActive: () => toggled = true,
              ),
              MembershipPlanRow(
                plan: const {
                  'name': 'Staff',
                  'plan_type': 'unlimited',
                  'duration_days': 30,
                  'is_active': false,
                },
                onOpenActions: () {},
                onToggleActive: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('8 credits · 30 days'), findsOneWidget);
    expect(find.text('Unlimited · 30 days'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.tap(find.text('Active'));
    expect(menuOpened, isTrue);
    expect(toggled, isTrue);
  });

  testWidgets('real plans manager opens the create form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: buildManagePlansSheetForTest(const [
            {
              'id': 'plan-1',
              'name': 'Beach',
              'plan_type': 'class_pack',
              'credits': 8,
              'duration_days': 30,
              'is_active': true,
            },
          ]),
        ),
      ),
    );

    await tester.tap(find.text('CREATE PLAN'));
    await tester.pump();

    expect(find.text('Plan name'), findsAtLeastNWidgets(1));
    expect(find.text('Plan type'), findsAtLeastNWidgets(1));
    expect(find.text('Credits'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });
}
