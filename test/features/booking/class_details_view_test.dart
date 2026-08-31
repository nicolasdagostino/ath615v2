import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/booking/presentation/booking_colors.dart';
import 'package:ath615v2/features/booking/presentation/widgets/attendance_add_booking_sheets.dart';
import 'package:ath615v2/features/booking/presentation/widgets/class_details_sheet.dart';
import 'package:ath615v2/features/booking/data/coach_briefing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });

  Map<String, dynamic> classData({
    Map<String, dynamic>? coach,
    String? description = 'Technique and strength work.',
  }) => <String, dynamic>{
    'id': 'class-1',
    'title': description?.isNotEmpty == true ? description : 'Fresh Start',
    'programs': {'name': 'Fresh Start'},
    'starts_at': '2030-08-22T07:00:00',
    'duration_minutes': 60,
    'capacity': 16,
    'coach_id': 'coach-1',
    'coach': coach ?? {'full_name': 'Jess Brown'},
  };

  final profiles = <String, Map<String, dynamic>>{
    'coach-1': {'full_name': 'Jess Brown', 'avatar_url': null},
    'athlete-1': {'full_name': 'Alex Duarte', 'avatar_url': null},
    'athlete-2': {'full_name': 'Laura Martín', 'avatar_url': null},
    'wait-1': {'full_name': 'Matías Ruiz', 'avatar_url': null},
    'wait-2': {'full_name': 'Nico Costa', 'avatar_url': null},
  };

  Widget details({
    ThemeMode mode = ThemeMode.light,
    double safeTop = 0,
    Map<String, dynamic>? klass,
    List<Map<String, dynamic>>? bookings,
    List<Map<String, dynamic>>? waitlist,
    Map<String, Map<String, dynamic>>? profileRows,
    String? actionLabel,
    VoidCallback? action,
    List<ClassDetailAdminAction> adminActions = const [],
    ClassDetailAttendeeActions? attendeeActions,
    ValueChanged<String>? onMemberTap,
    CoachBriefingClass? intelligence,
    Map<String, String> pinnedNotesByMember = const {},
    Future<void> Function()? onMarkAllAttended,
  }) {
    final roster =
        bookings ??
        [
          {'user_id': 'athlete-1', 'is_guest': false},
          {'user_id': 'athlete-2', 'is_guest': false},
          {'user_id': null, 'is_guest': true, 'guest_name': 'Guest Athlete'},
        ];
    final waiting =
        waitlist ??
        [
          {'user_id': 'wait-1'},
          {'user_id': 'wait-2'},
        ];

    return MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: EdgeInsets.only(top: safeTop)),
            child: SafeArea(
              bottom: false,
              child: ClassDetailsView(
                klass: klass ?? classData(),
                bookings: roster,
                waitlist: waiting,
                profilesById: profileRows ?? profiles,
                myWaitlistPosition: waiting.isEmpty ? null : 2,
                actionLabel: actionLabel ?? appStrings.bookingBook,
                onAction: action ?? () {},
                onBack: () {},
                adminActions: adminActions,
                attendeeActions: attendeeActions,
                onMemberTap: onMemberTap,
                intelligence: intelligence,
                pinnedNotesByMember: pinnedNotesByMember,
                onMarkAllAttended: onMarkAllAttended,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    ThemeMode mode = ThemeMode.light,
    Widget? child,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(child ?? details(mode: mode));
    await tester.pump();
  }

  testWidgets('renders class facts, coach, roster, waitlist and CTA', (
    tester,
  ) async {
    await pumpAt(tester);

    expect(find.text('Fresh Start'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.textContaining('22'), findsOneWidget);
    expect(find.text('60 MIN'), findsOneWidget);
    expect(find.text('JESS BROWN'), findsNothing);
    expect(find.text('Jess Brown'), findsOneWidget);
    expect(find.text('Technique and strength work.'), findsOneWidget);
    expect(
      find.text(appStrings.pick('ATTENDEES', 'ASISTENTES')),
      findsOneWidget,
    );
    expect(find.text(appStrings.waitlist), findsOneWidget);
    expect(find.text('Alex Duarte'), findsOneWidget);
    expect(find.text(appStrings.bookingBook.toUpperCase()), findsOneWidget);
    expect(find.byType(ClassDetailAdminButton), findsNothing);
    expect(find.byKey(const ValueKey('class-detail-add-member')), findsNothing);
    expect(find.byKey(const ValueKey('class-detail-add-guest')), findsNothing);

    expect(find.text('JB'), findsOneWidget);
    expect(find.text('AD'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final titleCenter = tester.getCenter(find.text('Fresh Start')).dx;
    expect(titleCenter, closeTo(195, 1));
    final header = tester.widget<Container>(
      find.byKey(const ValueKey('class-detail-header')),
    );
    expect(header.decoration, isNull);
    expect(
      tester.getTopLeft(find.text(appStrings.pick('Class', 'Clase'))).dy,
      lessThan(100),
    );
    final coachRow = tester.widget<ClassPersonRow>(
      find.byKey(const ValueKey('class-detail-coach')),
    );
    expect(coachRow.showDivider, isFalse);

    await tester.scrollUntilVisible(
      find.text('Matías Ruiz'),
      220,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Matías Ruiz'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('uses discreet fallbacks when coach and description are absent', (
    tester,
  ) async {
    await pumpAt(
      tester,
      child: details(
        klass: classData(coach: <String, dynamic>{}, description: ''),
        bookings: const [],
        waitlist: const [],
        profileRows: const {},
      ),
    );

    expect(
      find.text(appStrings.pick('No coach assigned', 'Sin coach asignado')),
      findsOneWidget,
    );
    expect(
      find.text(
        appStrings.pick('No description added.', 'No se añadió descripción.'),
      ),
      findsOneWidget,
    );
    expect(find.text(appStrings.noBookingsYet), findsOneWidget);
    expect(find.text(appStrings.waitlist), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unified detail renders today intelligence and pinned note', (
    tester,
  ) async {
    var markedAll = false;
    final now = DateTime.now();
    final intelligence = CoachBriefingClass(
      id: 'class-1',
      title: 'Fresh Start',
      startsAt: now.subtract(const Duration(minutes: 30)),
      localStartTime: '09:00',
      durationMinutes: 60,
      capacity: 16,
      coachName: 'Jess Brown',
      programName: 'Fresh Start',
      workoutDescription: '5 rounds\n10 pull-ups',
      booked: [
        CoachBriefingAthlete(
          bookingId: 'booking-1',
          userId: 'athlete-1',
          name: 'Alex Duarte',
          avatarUrl: null,
          isGuest: false,
          attendanceStatus: 'booked',
          firstClass: true,
          membershipUsable: true,
          membershipPlanType: 'class_pack',
          creditsRemaining: 1,
          membershipExpiresAt: now.add(const Duration(days: 2)),
        ),
        CoachBriefingAthlete(
          bookingId: 'booking-2',
          userId: 'athlete-2',
          name: 'Laura Martín',
          avatarUrl: null,
          isGuest: false,
          attendanceStatus: 'booked',
          firstClass: false,
          membershipUsable: false,
          membershipPlanType: null,
          creditsRemaining: null,
          membershipExpiresAt: null,
        ),
      ],
      waitlist: const [
        CoachBriefingWaitlistMember(
          userId: 'wait-1',
          name: 'Matías Ruiz',
          avatarUrl: null,
          position: 1,
        ),
      ],
    );
    await pumpAt(
      tester,
      child: details(
        klass: {
          ...classData(),
          'starts_at': now
              .subtract(const Duration(minutes: 30))
              .toIso8601String(),
        },
        bookings: const [
          {'id': 'booking-1', 'user_id': 'athlete-1', 'status': 'booked'},
          {'id': 'booking-2', 'user_id': 'athlete-2', 'status': 'booked'},
        ],
        intelligence: intelligence,
        pinnedNotesByMember: const {'athlete-1': 'Prefers Spanish cues.'},
        onMarkAllAttended: () async => markedAll = true,
      ),
    );

    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.textContaining('5 rounds'), findsOneWidget);
    expect(find.text('FIRST CLASS'), findsOneWidget);
    expect(find.text('1 CREDIT LEFT'), findsOneWidget);
    expect(find.textContaining('EXPIRES IN'), findsOneWidget);
    expect(find.text('NO MEMBERSHIP'), findsOneWidget);
    expect(find.text('NOTE'), findsOneWidget);

    await tester.tap(find.text('NOTE'));
    await tester.pumpAndSettle();
    expect(find.text('Prefers Spanish cues.'), findsOneWidget);
    Navigator.of(tester.element(find.text('Prefers Spanish cues.'))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('class-detail-mark-all-attended')),
      160,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(
      find.byKey(const ValueKey('class-detail-mark-all-attended')),
    );
    await tester.pump();
    expect(markedAll, isTrue);
  });

  testWidgets('fits at 320px in light and dark', (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await pumpAt(tester, size: const Size(320, 720), mode: mode);
      expect(find.text('Fresh Start'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      expect(find.text(appStrings.bookingBook.toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('bottom CTA preserves its callback', (tester) async {
    var tapped = false;
    await pumpAt(tester, child: details(action: () => tapped = true));

    await tester.tap(find.text(appStrings.bookingBook.toUpperCase()));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('admin member rows navigate while guests remain inert', (
    tester,
  ) async {
    String? openedMemberId;
    await pumpAt(
      tester,
      child: details(onMemberTap: (memberId) => openedMemberId = memberId),
    );

    await tester.tap(find.text('Alex Duarte'));
    await tester.pump();
    expect(openedMemberId, 'athlete-1');

    openedMemberId = null;
    await tester.tap(find.text('Guest Athlete'));
    await tester.pump();
    expect(openedMemberId, isNull);

    await tester.scrollUntilVisible(
      find.text('Matías Ruiz'),
      220,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Matías Ruiz'));
    await tester.pump();
    expect(openedMemberId, 'wait-1');
  });

  testWidgets('admin pencil opens the real contextual actions', (tester) async {
    var editTapped = false;
    var deleteTapped = false;
    await pumpAt(
      tester,
      child: details(
        adminActions: [
          ClassDetailAdminAction(
            icon: Icons.edit_outlined,
            label: appStrings.editClass,
            onTap: () => editTapped = true,
          ),
          ClassDetailAdminAction(
            icon: Icons.delete_outline_rounded,
            label: appStrings.deleteThisClass,
            destructive: true,
            onTap: () => deleteTapped = true,
          ),
        ],
      ),
    );

    expect(find.byType(ClassDetailAdminButton), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);

    final backCenter = tester.getCenter(
      find.byKey(const ValueKey('class-detail-back')),
    );
    final editCenter = tester.getCenter(find.byType(ClassDetailAdminButton));
    expect(editCenter.dy, backCenter.dy);
    expect(backCenter.dx, closeTo(48, 0.1));
    expect(editCenter.dx, closeTo(342, 0.1));

    await tester.tap(find.byType(ClassDetailAdminButton));
    await tester.pumpAndSettle();

    expect(find.byType(ClassDetailAdminSheet), findsOneWidget);
    expect(find.text(appStrings.editClass.toUpperCase()), findsOneWidget);
    expect(find.text(appStrings.deleteThisClass.toUpperCase()), findsOneWidget);
    expect(
      find.text(appStrings.deleteThisAndFuture.toUpperCase()),
      findsNothing,
    );
    expect(find.text(appStrings.addMember), findsNothing);
    expect(find.text(appStrings.addGuest), findsNothing);
    expect(find.text(appStrings.attendance), findsNothing);

    await tester.tap(find.text(appStrings.editClass.toUpperCase()));
    await tester.pumpAndSettle();
    expect(editTapped, isTrue);
    expect(deleteTapped, isFalse);
  });

  testWidgets('admin attendee actions are accessible and preserve callbacks', (
    tester,
  ) async {
    var memberTapped = false;
    var guestTapped = false;
    await pumpAt(
      tester,
      size: const Size(320, 720),
      child: details(
        adminActions: [
          ClassDetailAdminAction(
            icon: Icons.edit_outlined,
            label: appStrings.editClass,
            onTap: () {},
          ),
        ],
        attendeeActions: ClassDetailAttendeeActions(
          onAddMember: (_) async {
            memberTapped = true;
            return null;
          },
          onAddGuest: (_) async {
            guestTapped = true;
            return null;
          },
        ),
      ),
    );

    final member = find.byKey(const ValueKey('class-detail-add-member'));
    final guest = find.byKey(const ValueKey('class-detail-add-guest'));
    expect(member, findsOneWidget);
    expect(guest, findsOneWidget);
    expect(tester.getSize(member).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(member).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(guest).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(guest).height, greaterThanOrEqualTo(44));
    expect(find.byTooltip(appStrings.addMember), findsOneWidget);
    expect(find.byTooltip(appStrings.addGuest), findsOneWidget);

    await tester.tap(member);
    await tester.pump();
    expect(memberTapped, isTrue);
    expect(guestTapped, isFalse);
    await tester.tap(guest);
    await tester.pump();
    expect(guestTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete action delegates without bypassing its owner callback', (
    tester,
  ) async {
    var deleteTapped = false;
    await pumpAt(
      tester,
      child: details(
        adminActions: [
          ClassDetailAdminAction(
            icon: Icons.edit_outlined,
            label: appStrings.editClass,
            onTap: () {},
          ),
          ClassDetailAdminAction(
            icon: Icons.delete_outline_rounded,
            label: appStrings.deleteThisClass,
            destructive: true,
            onTap: () => deleteTapped = true,
          ),
        ],
      ),
    );

    await tester.tap(find.byType(ClassDetailAdminButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(appStrings.deleteThisClass.toUpperCase()));
    await tester.pumpAndSettle();
    expect(deleteTapped, isTrue);
  });

  testWidgets('recurring class sheet exposes the future delete action', (
    tester,
  ) async {
    await pumpAt(
      tester,
      child: details(
        adminActions: [
          ClassDetailAdminAction(
            icon: Icons.edit_outlined,
            label: appStrings.editClass,
            onTap: () {},
          ),
          ClassDetailAdminAction(
            icon: Icons.delete_outline_rounded,
            label: appStrings.deleteThisClass,
            destructive: true,
            onTap: () {},
          ),
          ClassDetailAdminAction(
            icon: Icons.delete_sweep_outlined,
            label: appStrings.deleteThisAndFuture,
            destructive: true,
            onTap: () {},
          ),
        ],
      ),
    );

    await tester.tap(find.byType(ClassDetailAdminButton));
    await tester.pumpAndSettle();
    expect(
      find.text(appStrings.deleteThisAndFuture.toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('add member opens directly without Attendance behind it', (
    tester,
  ) async {
    late BuildContext launchContext;
    await pumpAt(
      tester,
      size: const Size(320, 720),
      child: details(
        attendeeActions: ClassDetailAttendeeActions(
          onAddMember: (_) => showModalBottomSheet<Map<String, dynamic>>(
            context: launchContext,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => AttendanceAddMemberSheet(
              client: null,
              classId: 'class-1',
              membersLoader: (_) async => const [],
              memberAdder: (_) async => const {},
            ),
          ),
          onAddGuest: (_) async => null,
        ),
      ),
    );
    launchContext = tester.element(
      find.byKey(const ValueKey('class-detail-add-member')),
    );

    await tester.tap(find.byKey(const ValueKey('class-detail-add-member')));
    await tester.pumpAndSettle();
    expect(find.byType(AttendanceAddMemberSheet), findsOneWidget);
    expect(find.text(appStrings.attendance), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('booking-class-form-close')).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Fresh Start'), findsOneWidget);
    expect(find.byType(AttendanceAddMemberSheet), findsNothing);
    expect(find.text(appStrings.attendance), findsNothing);
  });

  testWidgets('add guest opens directly without Attendance behind it', (
    tester,
  ) async {
    late BuildContext launchContext;
    await pumpAt(
      tester,
      size: const Size(320, 720),
      child: details(
        attendeeActions: ClassDetailAttendeeActions(
          onAddMember: (_) async => null,
          onAddGuest: (_) => showModalBottomSheet<Map<String, dynamic>>(
            context: launchContext,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const AttendanceAddGuestSheet(),
          ),
        ),
      ),
    );
    launchContext = tester.element(
      find.byKey(const ValueKey('class-detail-add-guest')),
    );

    await tester.tap(find.byKey(const ValueKey('class-detail-add-guest')));
    await tester.pumpAndSettle();
    expect(find.byType(AttendanceAddGuestSheet), findsOneWidget);
    expect(find.text(appStrings.attendance), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('booking-class-form-close')).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Fresh Start'), findsOneWidget);
    expect(find.byType(AttendanceAddGuestSheet), findsNothing);
  });

  testWidgets('header stays below safe inset and edit hit target is tappable', (
    tester,
  ) async {
    const safeTop = 47.0;
    final actions = [
      ClassDetailAdminAction(
        icon: Icons.edit_outlined,
        label: appStrings.editClass,
        onTap: () {},
      ),
    ];
    await pumpAt(
      tester,
      child: details(safeTop: safeTop, adminActions: actions),
    );

    final back = find.byKey(const ValueKey('class-detail-back'));
    final edit = find.byType(ClassDetailAdminButton);
    final editRect = tester.getRect(edit);
    expect(tester.getRect(back).top, greaterThanOrEqualTo(safeTop));
    expect(editRect.top, greaterThanOrEqualTo(safeTop));
    expect(editRect.size.width, greaterThanOrEqualTo(44));
    expect(editRect.size.height, greaterThanOrEqualTo(44));
    expect(tester.getCenter(back).dy, tester.getCenter(edit).dy);

    for (final point in [
      editRect.center,
      editRect.centerLeft + const Offset(6, 0),
      editRect.centerLeft + const Offset(2, 0),
    ]) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.byType(ClassDetailAdminSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(ClassDetailAdminSheet))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('admin action sheet fits at 320px in dark mode', (tester) async {
    await pumpAt(
      tester,
      size: const Size(320, 720),
      child: details(
        mode: ThemeMode.dark,
        adminActions: [
          ClassDetailAdminAction(
            icon: Icons.edit_outlined,
            label: appStrings.editClass,
            onTap: () {},
          ),
          ClassDetailAdminAction(
            icon: Icons.delete_outline_rounded,
            label: appStrings.deleteThisClass,
            destructive: true,
            onTap: () {},
          ),
        ],
      ),
    );

    final pencil = tester.widget<Icon>(find.byIcon(Icons.edit_outlined).first);
    expect(pencil.color, BookingColors.primary);
    final backCenter = tester.getCenter(
      find.byKey(const ValueKey('class-detail-back')),
    );
    final editCenter = tester.getCenter(find.byType(ClassDetailAdminButton));
    expect(editCenter.dy, backCenter.dy);
    expect(backCenter.dx, closeTo(48, 0.1));
    expect(editCenter.dx, closeTo(272, 0.1));
    await tester.tap(find.byType(ClassDetailAdminButton));
    await tester.pumpAndSettle();

    expect(find.byType(ClassDetailAdminSheet), findsOneWidget);
    expect(find.text(appStrings.editClass.toUpperCase()), findsOneWidget);
    expect(find.text(appStrings.deleteThisClass.toUpperCase()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long attendee and waitlist lists remain scrollable', (
    tester,
  ) async {
    final bookings = List.generate(
      24,
      (index) => <String, dynamic>{
        'user_id': 'member-$index',
        'is_guest': false,
      },
    );
    final waitlist = List.generate(
      12,
      (index) => <String, dynamic>{'user_id': 'waiting-$index'},
    );
    final profileRows = <String, Map<String, dynamic>>{
      for (var index = 0; index < 24; index++)
        'member-$index': {'full_name': 'Member $index'},
      for (var index = 0; index < 12; index++)
        'waiting-$index': {'full_name': 'Waiting $index'},
    };

    await pumpAt(
      tester,
      size: const Size(320, 720),
      child: details(
        bookings: bookings,
        waitlist: waitlist,
        profileRows: profileRows,
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Waiting 11'),
      500,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Waiting 11'), findsOneWidget);
    expect(find.text(appStrings.bookingBook.toUpperCase()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
