import 'dart:io';
import 'dart:async';

import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_avatar.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:ath615v2/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('recent activity preserves booking cancellation identity and class', () {
    final rows = normalizeRecentActivityRows(const [
      {
        'kind': 'booking_cancelled',
        'member_name': 'Nicolás D’Agostino',
        'class_title': 'CrossFit',
        'class_starts_at': '2026-09-10T19:30:00Z',
      },
    ]);
    expect(rows.single['status'], 'cancelled');
    expect(rows.single['member_name'], 'Nicolás D’Agostino');
    expect(rows.single['classes'], {
      'title': 'CrossFit',
      'starts_at': '2026-09-10T19:30:00Z',
    });
  });

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

  test('request identity is deterministic and never crosses user records', () {
    const member = {
      'id': 'member-a',
      'full_name': 'Member Name',
      'email': 'member@example.com',
      'avatar_url': 'member.webp',
    };
    const profile = {
      'id': 'profile-a',
      'full_name': 'Profile Name',
      'email': 'profile@example.com',
      'avatar_url': 'profile.webp',
    };

    final explicit = adminRequestIdentity(
      const {
        'user_id': 'request-user',
        'member_name': 'Request Name',
        'member_email': 'request@example.com',
        'member_avatar_url': 'request.webp',
      },
      profile: profile,
      member: member,
      fallback: 'Member',
    );
    expect(explicit.name, 'Request Name');
    expect(explicit.email, 'request@example.com');
    expect(explicit.avatarUrl, 'request.webp');

    final fromProfile = adminRequestIdentity(
      const {'user_id': 'profile-a'},
      profile: profile,
      member: member,
      fallback: 'Member',
    );
    expect(fromProfile.name, 'Profile Name');
    expect(fromProfile.email, 'profile@example.com');

    final fromMember = adminRequestIdentity(
      const {'user_id': 'member-a'},
      member: member,
      fallback: 'Member',
    );
    expect(fromMember.name, 'Member Name');
    expect(fromMember.avatarUrl, 'member.webp');
  });

  test('request identity uses email then localized final fallback', () {
    final emailOnly = adminRequestIdentity(const {
      'member_email': 'known@example.com',
    }, fallback: 'Member');
    expect(emailOnly.name, 'known@example.com');
    expect(emailOnly.email, 'known@example.com');

    expect(adminRequestIdentity(const {}, fallback: 'Member').name, 'Member');
    expect(adminRequestIdentity(const {}, fallback: 'Miembro').name, 'Miembro');
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

  test(
    'Members exposes active/inactive filters and preserves data on deactivation',
    () {
      final source = File(
        'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
      ).readAsStringSync();
      expect(source, contains('_MemberRoleFilter.active'));
      expect(source, contains('_MemberRoleFilter.inactive'));
      expect(source, contains('Their profile and history will be preserved.'));
      expect(source, contains('This athlete has an active membership.'));
      expect(source, contains("'set_gym_member_active'"));
      expect(source, isNot(contains(".delete().eq('id', memberId)")));
    },
  );

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

  test(
    'membership approval refreshes before successful push dispatch',
    () async {
      final calls = <String>[];
      final pendingRequests = ['request-1'];

      await completeMembershipRequestApproval(
        approve: () async => calls.add('approve'),
        refresh: () async {
          calls.add('refresh');
          pendingRequests.clear();
        },
        sendNotification: () async => calls.add('push'),
      );

      expect(calls, ['approve', 'refresh', 'push']);
      expect(pendingRequests, isEmpty);
    },
  );

  test('push failure and timeout do not turn approval into failure', () async {
    for (final failure in <Object>[
      StateError('push failed'),
      TimeoutException('push timed out'),
    ]) {
      final calls = <String>[];
      final pendingRequests = ['request-1'];
      Object? reportedError;

      await completeMembershipRequestApproval(
        approve: () async => calls.add('approve'),
        refresh: () async {
          calls.add('refresh');
          pendingRequests.clear();
        },
        sendNotification: () async {
          calls.add('push');
          throw failure;
        },
        onNotificationError: (error, _) => reportedError = error,
      );

      expect(calls, ['approve', 'refresh', 'push']);
      expect(pendingRequests, isEmpty);
      expect(reportedError, same(failure));
    }
  });

  test('confirmed approval reconciles locally when refresh fails', () async {
    final calls = <String>[];
    final pendingRequests = ['request-1'];
    Object? reportedError;

    await completeMembershipRequestApproval(
      approve: () async => calls.add('approve'),
      refresh: () async {
        calls.add('refresh');
        throw StateError('refresh failed');
      },
      onRefreshError: (error, _) {
        reportedError = error;
        pendingRequests.remove('request-1');
      },
      sendNotification: () async => calls.add('push'),
    );

    expect(calls, ['approve', 'refresh', 'push']);
    expect(pendingRequests, isEmpty);
    expect(reportedError, isA<StateError>());
  });

  test(
    'RPC failure preserves pending state and never dispatches push',
    () async {
      final pendingRequests = ['request-1'];
      final calls = <String>[];

      await expectLater(
        completeMembershipRequestApproval(
          approve: () async {
            calls.add('approve');
            throw StateError('approval failed');
          },
          refresh: () async {
            calls.add('refresh');
            pendingRequests.clear();
          },
          sendNotification: () async => calls.add('push'),
        ),
        throwsStateError,
      );

      expect(calls, ['approve']);
      expect(pendingRequests, ['request-1']);
    },
  );

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

  testWidgets('membership approval loading uses the A615 primary color', (
    tester,
  ) async {
    const request = {
      'id': 'request-1',
      'member_name': 'Laia Member',
      'plan_name': '5 Classes',
      'amount_total': 3500,
      'currency': 'eur',
    };

    Future<void> pumpOverview({String? processingRequestId}) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: buildMembershipOverviewForTest(
              requests: const [request],
              processingRequestId: processingRequestId,
            ),
          ),
        ),
      );
    }

    await pumpOverview();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await pumpOverview(processingRequestId: 'request-1');
    final loading = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(loading.color, AppColors.primary);
    expect(loading.strokeWidth, 2);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await pumpOverview();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('membership request renders exact identity in management', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: buildMembershipOverviewForTest(
            requests: const [
              {
                'id': 'request-a',
                'user_id': 'user-a',
                'member_name': 'Ada Athlete',
                'member_email': 'ada@example.com',
                'member_avatar_url': '',
                'plan_name': 'Pack 5',
              },
              {
                'id': 'request-b',
                'user_id': 'user-b',
                'member_name': 'Bea Athlete',
                'member_email': 'bea@example.com',
                'member_avatar_url': '',
                'plan_name': 'Drop-in',
              },
            ],
          ),
        ),
      ),
    );

    expect(find.text('Ada Athlete'), findsOneWidget);
    expect(find.textContaining('ada@example.com'), findsOneWidget);
    expect(find.text('Bea Athlete'), findsOneWidget);
    expect(find.textContaining('bea@example.com'), findsOneWidget);
    expect(find.byType(AppAvatar), findsNWidgets(2));
  });

  testWidgets(
    'overview action sheet preserves join and membership identities',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildDashboardOverviewForTest(
                joinRequests: const [
                  {
                    'id': 'join-a',
                    'member_name': 'Join Person',
                    'member_email': 'join@example.com',
                  },
                ],
                membershipRequests: const [
                  {
                    'id': 'membership-a',
                    'member_name': 'Membership Person',
                    'member_email': 'membership@example.com',
                    'plan_name': 'Pack 5',
                  },
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('dashboard-attention')));
      await tester.pumpAndSettle();

      expect(find.text('Join Person'), findsOneWidget);
      expect(find.textContaining('join@example.com'), findsOneWidget);
      expect(find.text('Membership Person'), findsOneWidget);
      expect(find.textContaining('membership@example.com'), findsOneWidget);
    },
  );
}
