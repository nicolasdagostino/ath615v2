import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/members/presentation/widgets/member_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject(Map<String, dynamic> member) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MemberListRow(member: member, onTap: () {}, onMore: () {}),
        ),
      ),
    );
  }

  testWidgets('renders active athlete with membership metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject({
        'full_name': 'Lucila Laplaze',
        'email': 'lucila@example.com',
        'role': 'athlete',
        'is_active': true,
        'is_coach': false,
        'membership_name': 'Beach',
        'credits_remaining': 1,
      }),
    );

    expect(find.text('Lucila Laplaze'), findsOneWidget);
    expect(find.text('lucila@example.com'), findsOneWidget);
    expect(find.text('Beach · 1 credit'), findsOneWidget);
    expect(find.textContaining('Active · Athlete'), findsOneWidget);
  });

  testWidgets('renders admin and Coach capabilities without large badges', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject({
        'full_name': 'Martina Fernández',
        'email': 'martina@example.com',
        'role': 'admin',
        'is_active': true,
        'is_coach': true,
      }),
    );

    expect(find.textContaining('Active · Admin · COACH'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('renders inactive state and fallback avatar at 360 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      subject({
        'full_name': 'Maite Sastre',
        'email': 'a-very-long-email-address@example.com',
        'role': 'coach',
        'is_active': false,
        'is_coach': false,
      }),
    );

    expect(find.text('M'), findsOneWidget);
    expect(find.textContaining('Inactive · COACH'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more action keeps a 44 px touch target', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MemberListRow(
            member: const {
              'full_name': 'Alex Member',
              'email': 'alex@example.com',
              'role': 'athlete',
              'is_active': true,
            },
            onTap: () {},
            onMore: () => pressed = true,
          ),
        ),
      ),
    );

    final button = find.byType(IconButton);
    expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    await tester.tap(button);
    expect(pressed, isTrue);
  });
}
