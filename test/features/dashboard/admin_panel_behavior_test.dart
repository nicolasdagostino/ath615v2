import 'dart:io';

import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:ath615v2/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('without-plan counter and filter share the exact predicate', () {
    final members = List.generate(28, (index) {
      final withoutPlan = index < 20;
      return <String, dynamic>{
        'id': '$index',
        'role': 'athlete',
        'is_active': true,
        'membership_name': withoutPlan ? null : 'Unlimited',
      };
    });

    final counterRows = members.where(adminMemberIsWithoutActivePlan).toList();
    final filteredRows = members.where(adminMemberIsWithoutActivePlan).toList();

    expect(counterRows, hasLength(20));
    expect(
      filteredRows.map((row) => row['id']),
      counterRows.map((row) => row['id']),
    );
    expect(members, hasLength(28));
  });

  test('access request name uses full name, then email, then fallback', () {
    expect(
      adminAccessRequestDisplayName(const {
        'full_name': "Nicolás D'Agostino",
        'email': 'n@example.com',
      }, fallback: 'Member'),
      "Nicolás D'Agostino",
    );
    expect(
      adminAccessRequestDisplayName(const {
        'full_name': ' ',
        'email': 'n@example.com',
      }, fallback: 'Member'),
      'n@example.com',
    );
    expect(adminAccessRequestDisplayName(null, fallback: 'Member'), 'Member');
  });

  testWidgets('today classes expose their program in the real overview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(child: buildDashboardOverviewForTest()),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('today-class-program-CrossFit')),
      findsOneWidget,
    );
    expect(find.text('Available · 2/10'), findsOneWidget);
    expect(find.text('8 spots available'), findsOneWidget);
    expect(find.text('WAITLIST · 1'), findsOneWidget);
    expect(find.text('Coach Alex'), findsOneWidget);
  });

  testWidgets('today classes share occupancy states and open class detail', (
    tester,
  ) async {
    Map<String, dynamic>? opened;
    List<Map<String, dynamic>> rows(int count) =>
        List.generate(count, (index) => {'id': 'booking-$count-$index'});

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: buildDashboardOverviewForTest(
              todayClassRows: [
                {
                  'id': 'available',
                  'title': 'Technique',
                  'starts_at': '2026-08-14T17:00:00Z',
                  'capacity': 10,
                  'booking_rows': rows(4),
                  'waitlist_rows': const [],
                  'programs': {'name': 'CrossFit'},
                },
                {
                  'id': 'almost',
                  'title': 'Conditioning',
                  'starts_at': '2026-08-14T18:00:00Z',
                  'capacity': 10,
                  'booking_rows': rows(8),
                  'waitlist_rows': const [],
                  'programs': {'name': 'WOD'},
                },
                {
                  'id': 'full',
                  'title': 'Strength',
                  'starts_at': '2026-08-14T19:00:00Z',
                  'capacity': 10,
                  'booking_rows': rows(10),
                  'waitlist_rows': const [],
                  'programs': {'name': 'Weightlifting'},
                },
              ],
              onOpenTodayClass: (klass) async => opened = klass,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Available · 4/10'), findsOneWidget);
    expect(find.text('Almost full · 8/10'), findsOneWidget);
    expect(find.text('Full · 10/10'), findsOneWidget);

    await tester.tap(find.text('Technique'));
    await tester.pump();
    expect(opened?['id'], 'available');
  });

  testWidgets('communication uses shared form fields and primary submit CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: buildAdminCommunicationSheetForTest()),
      ),
    );

    expect(find.text('SEND COMMUNICATION'), findsAtLeastNWidgets(1));
    expect(find.byType(TextField), findsNWidgets(2));
    final submit = tester.widget<AppFormSubmitButton>(
      find.byType(AppFormSubmitButton),
    );
    expect(submit.accentColor, AppColors.primary);
    expect(tester.takeException(), isNull);
  });

  test('member invite and membership admin use shared primary forms', () {
    final source = File(
      'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
    ).readAsStringSync();

    expect(source, contains('showAppLargeFormSheet<void>('));
    expect(source, contains('title: appStrings.inviteAthlete'));
    expect(source, contains('style: appFormValueStyle(context)'));
    expect(source, contains('appStrings.coachRoleLabel'));
    expect(source, contains('appStrings.adminRoleLabel'));
    expect(source, contains("'member-since-label'"));
    expect(source, contains("member['gym_member_created_at']"));
    expect(
      source,
      isNot(contains("_formatDate(member['created_at']?.toString())")),
    );
    expect(source, contains('label: appStrings.assignPlan'));
    expect(source, contains("'member-detail-assign-plan'"));
    expect(source, contains("'membership-manage-plans'"));
    expect(source, contains('AppFormSubmitButton('));
    expect(source, contains('backgroundColor: AppColors.primary'));

    final memberSource = File(
      'supabase/functions/admin-list-members/index.ts',
    ).readAsStringSync();
    expect(memberSource, contains('.from("gym_members")'));
    expect(memberSource, contains('.eq("gym_id", adminProfile.gym_id)'));
    expect(memberSource, contains('gym_member_created_at:'));
  });

  test('member since uses gym membership creation, never profile creation', () {
    final joined = adminGymMemberCreatedAt({
      'created_at': '2024-01-10T00:00:00Z',
      'gym_member_created_at': '2026-08-13T00:00:00Z',
    });

    expect(joined, DateTime.utc(2026, 8, 13));
    expect(adminGymMemberCreatedAt({'created_at': '2024-01-10'}), isNull);
  });

  test('only pending in-person requests require admin action', () {
    expect(
      adminMembershipRequestNeedsAction(const {
        'status': 'pending',
        'payment_method': 'cash',
        'payment_status': 'pending',
      }),
      isTrue,
    );
    expect(
      adminMembershipRequestNeedsAction(const {
        'status': 'pending',
        'payment_method': 'card',
        'payment_status': 'pending',
      }),
      isFalse,
    );
    expect(
      adminMembershipRequestPriceLabel(const {
        'amount_total': 3500,
        'currency': 'eur',
      }),
      '35.00 EUR',
    );
  });

  testWidgets('manual request offers explicit payment confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: buildMembershipOverviewForTest(
            requests: const [
              {
                'id': 'request-1',
                'member_name': 'Laia Member',
                'plan_name': '5 Classes',
                'amount_total': 3500,
                'currency': 'eur',
              },
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('In-person payment'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('CONFIRM PAYMENT AND ACTIVATE'), findsOneWidget);
    expect(find.text('REJECT'), findsOneWidget);
  });
}
