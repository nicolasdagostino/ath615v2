import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/profile/presentation/screens/profile_screen.dart';
import 'package:ath615v2/features/profile/presentation/screens/attendance_history_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  ProfileOverviewData data({String? avatarUrl, String? logoUrl}) =>
      ProfileOverviewData(
        profile: {
          'full_name': 'Nicolás D’Agostino With A Long Athlete Name',
          'email': 'nicolas@example.com',
          'avatar_url': avatarUrl,
          'role': 'athlete',
          'gym_id': 'gym-1',
        },
        gym: {
          'name': 'ATHLETE615 Training Center With A Long Name',
          'logo_url': logoUrl,
        },
        attendances: [
          ProfileAttendance(startsAt: DateTime(2026, 8, 12), className: 'A'),
          ProfileAttendance(startsAt: DateTime(2026, 8, 1), className: 'B'),
          ProfileAttendance(startsAt: DateTime(2026, 1, 3), className: 'C'),
          ProfileAttendance(startsAt: DateTime(2025, 12, 30), className: 'D'),
        ],
      );

  Future<void> pumpOverview(
    WidgetTester tester, {
    required ThemeMode mode,
    String? avatarUrl,
    String? logoUrl,
    VoidCallback? onSettings,
    VoidCallback? onMemberships,
    VoidCallback? onRecords,
    VoidCallback? onAttendanceHistory,
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
        home: Scaffold(
          body: ProfileOverview(
            data: data(avatarUrl: avatarUrl, logoUrl: logoUrl),
            fallbackGymName: 'Fallback gym',
            uploadingAvatar: false,
            onAvatarTap: () {},
            onSettings: onSettings ?? () {},
            onMemberships: onMemberships ?? () {},
            onRecords: onRecords ?? () {},
            onAttendanceHistory: onAttendanceHistory ?? () {},
            nowForTesting: DateTime(2026, 8, 13),
          ),
        ),
      ),
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('profile overview fits 320px in ${mode.name}', (tester) async {
      await pumpOverview(tester, mode: mode);

      final headerFinder = find.byKey(const ValueKey('profile-primary-header'));
      final headerColor = tester.widget<ColoredBox>(
        find.descendant(of: headerFinder, matching: find.byType(ColoredBox)),
      );
      expect(headerColor.color, AppColors.primary);
      final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.ancestor(
          of: headerFinder,
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      expect(overlay.value.statusBarColor, AppColors.primary);
      expect(
        find.descendant(
          of: find.byType(Scrollable),
          matching: find.byType(ProfilePrimaryHeader),
        ),
        findsNothing,
      );
      final headerTopBefore = tester.getTopLeft(headerFinder).dy;
      expect(find.byKey(const ValueKey('profile-avatar-fallback')), findsOne);
      expect(find.text('ND'), findsOne);
      expect(find.byKey(const ValueKey('profile-display-name')), findsOne);
      expect(find.byKey(const ValueKey('profile-email')), findsOne);
      expect(find.text('nicolas@example.com'), findsOne);
      expect(find.byKey(const ValueKey('profile-gym-identity')), findsOne);
      final gymNameFinder = find.byKey(const ValueKey('profile-gym-name'));
      final gymName = tester.widget<Text>(gymNameFinder);
      expect(gymName.textAlign, TextAlign.center);
      final gymBlock = find.byKey(const ValueKey('profile-gym-identity'));
      expect(tester.getSize(gymBlock).height, lessThan(110));
      expect(tester.getCenter(gymNameFinder).dx, closeTo(160, 1));
      final gymContent = find.byKey(const ValueKey('profile-gym-content'));
      expect(
        tester.getCenter(gymContent).dy,
        closeTo(tester.getCenter(gymBlock).dy, 1),
      );
      expect(find.byKey(const ValueKey('profile-gym-label')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-gym-role')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-gym-logo-fallback')),
        findsNothing,
      );
      expect(tester.getSize(gymBlock).height, lessThan(110));
      expect(find.byKey(const ValueKey('profile-milestone')), findsOne);
      expect(find.text('4 / 50'), findsOne);
      expect(
        find.byKey(const ValueKey('profile-membership-card-disabled')),
        findsOne,
      );
      expect(find.textContaining('Coming soon'), findsOne);
      final viewAll = tester.widget<Text>(find.text('VIEW ALL'));
      expect(viewAll.style?.color, AppColors.primary);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-attendance-total')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getTopLeft(headerFinder).dy, headerTopBefore);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-attendance-week')),
          matching: find.text('1'),
        ),
        findsOne,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-attendance-month')),
          matching: find.text('2'),
        ),
        findsOne,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-attendance-year')),
          matching: find.text('3'),
        ),
        findsOne,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-attendance-total')),
          matching: find.text('4'),
        ),
        findsOne,
      );
    });
  }

  testWidgets('avatar, name and settings remain in the fixed hero', (
    tester,
  ) async {
    await pumpOverview(tester, mode: ThemeMode.light);
    final header = find.byKey(const ValueKey('profile-primary-header'));
    final avatar = find.byKey(const ValueKey('profile-avatar'));
    final scrollable = find.byType(Scrollable).first;
    final headerBottom = tester.getBottomLeft(header).dy;
    final avatarBefore = tester.getRect(avatar);
    final nameBefore = tester.getTopLeft(
      find.byKey(const ValueKey('profile-display-name')),
    );
    final settingsBefore = tester.getTopLeft(
      find.byKey(const ValueKey('profile-settings-button')),
    );

    expect(avatarBefore.top, lessThan(headerBottom));
    expect(avatarBefore.bottom, greaterThan(headerBottom));
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pump();
    expect(tester.getTopLeft(header).dy, 0);
    expect(tester.getRect(avatar), avatarBefore);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('profile-display-name'))),
      nameBefore,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('profile-settings-button'))),
      settingsBefore,
    );
  });

  testWidgets('gym and compact records are the first scrolling blocks', (
    tester,
  ) async {
    await pumpOverview(tester, mode: ThemeMode.light);
    final gym = find.byKey(const ValueKey('profile-gym-identity'));
    final records = find.byKey(const ValueKey('profile-records-action'));
    expect(
      tester.getTopLeft(records).dy,
      greaterThan(tester.getBottomLeft(gym).dy),
    );
    expect(tester.getSize(records).width, tester.getSize(gym).width);
    expect(tester.getSize(records).height, lessThan(80));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-overview-scroll')),
        matching: gym,
      ),
      findsOne,
    );
  });

  testWidgets('scroll viewport clips content below the opaque fixed hero', (
    tester,
  ) async {
    await pumpOverview(tester, mode: ThemeMode.light);
    final hero = find.byKey(const ValueKey('profile-fixed-hero'));
    final viewport = find.byKey(const ValueKey('profile-scroll-viewport'));
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('profile-overview-scroll')),
    );
    final fixedTop = tester.getTopLeft(hero).dy;
    final fixedBottom = tester.getBottomLeft(hero).dy;

    expect(list.clipBehavior, Clip.hardEdge);
    expect(tester.getTopLeft(viewport).dy, fixedBottom);
    expect(
      tester.widget<ColoredBox>(viewport).color,
      AppColors.background(tester.element(viewport)),
    );

    await tester.drag(
      find.byKey(const ValueKey('profile-overview-scroll')),
      const Offset(0, -260),
    );
    await tester.pump();
    expect(tester.getTopLeft(hero).dy, fixedTop);
    expect(tester.getBottomLeft(hero).dy, fixedBottom);
    expect(tester.getTopLeft(viewport).dy, fixedBottom);
    expect(find.byKey(const ValueKey('profile-avatar')), findsOne);
    expect(find.byKey(const ValueKey('profile-display-name')), findsOne);
    expect(find.byKey(const ValueKey('profile-settings-button')), findsOne);
  });

  testWidgets('settings and memberships actions preserve their callbacks', (
    tester,
  ) async {
    var settingsOpened = false;
    var membershipsOpened = false;
    var attendanceOpened = false;
    var recordsOpened = false;
    await pumpOverview(
      tester,
      mode: ThemeMode.light,
      onSettings: () => settingsOpened = true,
      onMemberships: () => membershipsOpened = true,
      onAttendanceHistory: () => attendanceOpened = true,
      onRecords: () => recordsOpened = true,
    );

    await tester.tap(find.byKey(const ValueKey('profile-settings-button')));
    expect(settingsOpened, isTrue);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-memberships-action')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -80));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-memberships-action')));
    expect(membershipsOpened, isTrue);

    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('profile-records-action'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-records-action')));
    expect(recordsOpened, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('profile-membership-card-disabled')),
    );
    expect(membershipsOpened, isTrue);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-attendance-view-all')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('profile-attendance-view-all')));
    expect(attendanceOpened, isTrue);
  });

  testWidgets('settings uses the lighter outlined Cupertino gear', (
    tester,
  ) async {
    await pumpOverview(tester, mode: ThemeMode.light);
    final icon = tester.widget<Icon>(find.byIcon(CupertinoIcons.gear));
    expect(
      icon.color,
      AppColors.textPrimary(tester.element(find.byIcon(CupertinoIcons.gear))),
    );
    expect(icon.size, 22);
  });

  test('only attended rows contribute to Profile attendance and milestone', () {
    final confirmed = confirmedAttendanceRows(const [
      {'status': 'booked'},
      {'status': 'attended'},
      {'status': 'no_show'},
      {'status': 'attended'},
    ]);
    expect(confirmed, hasLength(2));
    expect(confirmed.every((row) => row['status'] == 'attended'), isTrue);
  });

  testWidgets('real avatar loads while Profile omits the gym logo', (
    tester,
  ) async {
    await pumpOverview(
      tester,
      mode: ThemeMode.light,
      avatarUrl: 'https://example.com/avatar.jpg',
      logoUrl: 'https://example.com/logo.jpg',
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(1));
    expect(
      images.map((image) => (image.image as NetworkImage).url),
      contains('https://example.com/avatar.jpg'),
    );
    expect(
      images.map((image) => (image.image as NetworkImage).url),
      isNot(contains('https://example.com/logo.jpg')),
    );
  });
}
