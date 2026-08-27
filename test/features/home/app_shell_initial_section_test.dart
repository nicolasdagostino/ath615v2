import 'package:ath615v2/features/home/presentation/screens/app_shell.dart';
import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpShell(
    WidgetTester tester,
    String role, {
    int unread = 0,
    String? initialSection,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          key: ValueKey('shell-$role-$unread-$initialSection'),
          initialRoleForTesting: role,
          initialUnreadForTesting: unread,
          initialSection: initialSection,
          screenBuilderForTesting: (section) => ColoredBox(
            color: Colors.transparent,
            child: Center(
              child: Text(section, key: ValueKey('screen-$section')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('admin opens directly on Dashboard', (tester) async {
    await pumpShell(tester, 'admin');

    expect(find.byKey(const ValueKey('screen-dashboard')), findsOneWidget);
    expect(find.byIcon(Icons.dashboard), findsOneWidget);
    expect(find.byKey(const ValueKey('screen-booking')), findsNothing);
  });

  testWidgets('messages is a primary destination for every role', (
    tester,
  ) async {
    await pumpShell(tester, 'athlete');

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pump();

    expect(find.byKey(const ValueKey('screen-messages')), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
  });

  testWidgets('communication deep link opens messages inside the shell', (
    tester,
  ) async {
    await pumpShell(tester, 'admin', initialSection: 'messages');
    expect(find.byKey(const ValueKey('screen-messages')), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
    expect(initialShellIndexForRole('admin', requestedSection: 'messages'), 2);
    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
  });

  testWidgets('messages badge is numeric and hidden at zero', (tester) async {
    await pumpShell(tester, 'athlete', unread: 8);
    expect(find.text('8'), findsOneWidget);

    await pumpShell(tester, 'athlete');
    expect(find.text('8'), findsNothing);
  });

  testWidgets('membership deep link opens the admin membership section', (
    tester,
  ) async {
    await pumpShell(tester, 'admin', initialSection: 'membership');
    expect(find.byKey(const ValueKey('screen-dashboard')), findsOneWidget);
    expect(
      initialShellIndexForRole('admin', requestedSection: 'membership'),
      4,
    );
    expect(
      initialShellIndexForRole('athlete', requestedSection: 'membership'),
      1,
    );
  });

  testWidgets('WOD date deep link selects the workouts destination', (
    tester,
  ) async {
    await pumpShell(tester, 'athlete', initialSection: 'wod');
    expect(find.byKey(const ValueKey('screen-workouts')), findsOneWidget);
    expect(initialShellIndexForRole('athlete', requestedSection: 'wod'), 0);
  });

  testWidgets('athlete opens directly on Booking', (tester) async {
    await pumpShell(tester, 'athlete');

    expect(find.byKey(const ValueKey('screen-booking')), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    expect(find.byKey(const ValueKey('screen-dashboard')), findsNothing);
    expect(find.text('ANALYTICS'), findsNothing);
  });

  testWidgets(
    'owner uses Dashboard when rendered in the administrative shell',
    (tester) async {
      await pumpShell(tester, 'owner');

      expect(find.byKey(const ValueKey('screen-dashboard')), findsOneWidget);
      expect(find.byIcon(Icons.dashboard), findsOneWidget);
    },
  );

  testWidgets('manual navigation remains available after role initialization', (
    tester,
  ) async {
    await pumpShell(tester, 'admin');

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pump();

    expect(find.byKey(const ValueKey('screen-booking')), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month), findsOneWidget);
  });

  testWidgets('tapping Panel clears a transient member detail destination', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          initialRoleForTesting: 'admin',
          initialDashboardMemberIdForTesting: 'member-1',
          screenBuilderForTesting: (section) =>
              Text(section, key: ValueKey('screen-$section')),
          dashboardScreenBuilderForTesting: (section, memberId) => Text(
            memberId == null ? 'DASHBOARD ROOT' : 'MEMBER $memberId',
            key: ValueKey('dashboard-${memberId ?? 'root'}'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MEMBER member-1'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pump();
    expect(find.byKey(const ValueKey('screen-booking')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dashboard_outlined));
    await tester.pump();
    expect(find.text('DASHBOARD ROOT'), findsOneWidget);
    expect(find.text('MEMBER member-1'), findsNothing);
  });

  testWidgets('selected destination uses the shared primary instead of gold', (
    tester,
  ) async {
    await pumpShell(tester, 'athlete');

    final selected = tester.widget<Icon>(find.byIcon(Icons.calendar_month));
    expect(selected.color, AppColors.primary);
    expect(selected.color, isNot(AppColors.accent));

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pump();
    final profile = tester.widget<Icon>(find.byIcon(Icons.person));
    expect(profile.color, AppColors.primary);
  });

  testWidgets('shell exposes one workouts destination and no Explore tab', (
    tester,
  ) async {
    await pumpShell(tester, 'athlete');

    expect(find.byIcon(Icons.search_outlined), findsNothing);
    expect(find.byKey(const ValueKey('screen-explore')), findsNothing);
    await tester.tap(find.byIcon(Icons.fitness_center_outlined));
    await tester.pump();
    expect(find.byKey(const ValueKey('screen-workouts')), findsOneWidget);
  });

  testWidgets('a fresh session does not retain the previous user tab', (
    tester,
  ) async {
    await pumpShell(tester, 'admin');
    expect(find.byKey(const ValueKey('screen-dashboard')), findsOneWidget);

    await pumpShell(tester, 'athlete');
    expect(find.byKey(const ValueKey('screen-booking')), findsOneWidget);
    expect(find.byKey(const ValueKey('screen-dashboard')), findsNothing);
  });
}
