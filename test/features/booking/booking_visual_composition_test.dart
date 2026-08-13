import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_async_state.dart';
import 'package:ath615v2/core/widgets/app_selected_date_label.dart';
import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_class_card.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_create_class_button.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_day_chips.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_header.dart';
import 'package:ath615v2/core/widgets/app_section_chip.dart';
import 'package:ath615v2/features/booking/presentation/booking_colors.dart';
import 'package:ath615v2/features/booking/presentation/widgets/membership_status_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await localeController.setLanguage('en');
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });

  Widget composition({bool canCreateClass = true}) {
    final day = DateTime(2030, 8, 12);
    final classes = [
      (
        klass: <String, dynamic>{
          'title': 'Cross Training',
          'starts_at': '2030-08-12T07:30:00Z',
          'coach': {'full_name': 'Alma'},
          'programs': {'name': 'Strength'},
        },
        booked: 8,
        capacity: 12,
        label: appStrings.bookingBook,
        action: () {},
        waitlist: null,
      ),
      (
        klass: <String, dynamic>{
          'title': 'Operation LFG',
          'starts_at': '2030-08-12T09:00:00Z',
          'coach': {'full_name': 'Nicolás'},
        },
        booked: 12,
        capacity: 12,
        label: appStrings.bookingJoinWaitlist,
        action: () {},
        waitlist: 2,
      ),
      (
        klass: <String, dynamic>{
          'title': 'Mobility',
          'starts_at': '2030-08-12T11:00:00Z',
        },
        booked: 4,
        capacity: 10,
        label: appStrings.bookingBooked,
        action: null,
        waitlist: null,
      ),
    ];

    return Scaffold(
      body: Column(
        children: [
          BookingHeader(gymName: 'Test Gym'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: BookingClassesChip(),
          ),
          const Divider(indent: 24, endIndent: 24),
          BookingDayChips(
            selectedDay: day,
            canViewPastDays: true,
            onSelected: (_) {},
          ),
          BookingSelectedDateLabel(selectedDay: day),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: classes
                  .map(
                    (item) => BookingClassCard(
                      klass: item.klass,
                      bookedCount: item.booked,
                      capacity: item.capacity,
                      buttonLabel: item.label,
                      buttonAction: item.action,
                      waitlistPosition: item.waitlist,
                      onTap: () {},
                      formatDateTime: (raw) => raw,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
      floatingActionButton: canCreateClass
          ? BookingCreateClassButton(onPressed: () {})
          : null,
    );
  }

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: composition()),
    );
  }

  testWidgets('booking composition fits at 390x844', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.text(appStrings.bookingTitle.toUpperCase()), findsNothing);
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    expect(find.byIcon(Icons.notifications), findsNothing);
    expect(find.byType(MembershipStatusCard), findsNothing);
    expect(find.textContaining('Unlimited'), findsNothing);
    expect(find.text('AUGUST 2030'), findsNothing);
    expect(find.text('MONDAY, 12 AUGUST 2030'), findsOneWidget);
    expect(find.text('CLASSES'), findsOneWidget);
    expect(find.text('MON'), findsWidgets);
    expect(find.text('TUE'), findsWidgets);
    expect(find.text('WED'), findsWidgets);
    expect(find.text('THU'), findsWidgets);
    expect(find.text('FRI'), findsWidgets);
    expect(find.text('SAT'), findsWidgets);
    expect(find.text('SUN'), findsWidgets);
    expect(find.text('COACH · Alma'), findsNothing);
    expect(find.text('STRENGTH'), findsOneWidget);
    expect(find.text('Cross Training'), findsOneWidget);
    expect(find.textContaining('8 / 12'), findsOneWidget);
    expect(find.text(appStrings.bookingBook.toUpperCase()), findsOneWidget);
    expect(
      find.text(appStrings.bookingJoinWaitlist.toUpperCase()),
      findsOneWidget,
    );
    expect(
      find.text(appStrings.bookingBooked.toUpperCase()),
      findsAtLeastNWidgets(1),
    );
    final classesTop = tester.getTopLeft(find.text('CLASSES')).dy;
    final weekdaysTop = tester.getTopLeft(find.text('MON').first).dy;
    expect(classesTop, lessThan(weekdaysTop));

    final gymFinder = find.text('TEST GYM');
    final gymCenter = tester.getCenter(gymFinder).dx;
    expect(gymCenter, closeTo(195, 1));
    final headerBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(BookingHeader),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(headerBox.color, BookingColors.primary);
    final classesChip = tester.widget<AppSectionChip>(
      find.byKey(const ValueKey('booking-classes-chip')),
    );
    expect(classesChip.selected, isTrue);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    expect(find.byType(BookingCreateClassButton), findsOneWidget);

    final programText = tester.widget<Text>(find.text('STRENGTH'));
    final classText = tester.widget<Text>(find.text('Cross Training'));
    expect(
      programText.style?.fontSize ?? 0,
      greaterThan(classText.style?.fontSize ?? double.infinity),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking composition fits at 360x800', (tester) async {
    await pumpAt(tester, const Size(360, 800));
    await tester.drag(find.byType(ListView).last, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('MOBILITY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking cards fit at 320px in light and dark', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: composition(),
        ),
      );
      await tester.pump();
      expect(find.text('CLASSES'), findsOneWidget);
      expect(find.text('STRENGTH'), findsOneWidget);
      expect(find.text('MONDAY, 12 AUGUST 2030'), findsOneWidget);
      expect(find.byType(MembershipStatusCard), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('classes chip and selected date follow the active locale', (
    tester,
  ) async {
    addTearDown(() => localeController.setLanguage('en'));

    await localeController.setLanguage('es');
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('CLASES'), findsOneWidget);
    expect(find.text('LUNES, 12 AGOSTO 2030'), findsOneWidget);
    expect(find.byType(AppSelectedDateLabel), findsOneWidget);

    await localeController.setLanguage('en');
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('CLASSES'), findsOneWidget);
    expect(find.text('MONDAY, 12 AUGUST 2030'), findsOneWidget);
  });

  testWidgets('athlete composition has no create or overflow menu actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: composition(canCreateClass: false),
      ),
    );

    expect(find.byType(BookingCreateClassButton), findsNothing);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
  });

  testWidgets('selected booking day uses the local blue accent', (
    tester,
  ) async {
    final today = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BookingDayChips(selectedDay: today, onSelected: (_) {}),
        ),
      ),
    );

    final selectedDay = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('booking-selected-day')),
    );
    expect(
      (selectedDay.decoration! as BoxDecoration).color,
      BookingColors.primary,
    );
  });

  testWidgets('booking empty state uses the shared async pattern', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppAsyncState.empty(
            icon: Icons.event_busy_outlined,
            message: appStrings.restDayMessage,
          ),
        ),
      ),
    );
    expect(find.byType(AppAsyncState), findsOneWidget);
    expect(find.text(appStrings.restDayMessage), findsOneWidget);
  });
}
