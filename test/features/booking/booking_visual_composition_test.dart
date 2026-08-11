import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_async_state.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_class_card.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_day_chips.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_header.dart';
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

  Widget composition() {
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
          BookingHeader(
            gymName: 'Test Gym',
            selectedDay: day,
            unreadNotifications: 1,
            onOpenNotifications: () {},
          ),
          BookingDayChips(
            selectedDay: day,
            canViewPastDays: true,
            onSelected: (_) {},
          ),
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
                      onMorePressed: () {},
                      formatDateTime: (raw) => raw,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add_rounded),
        label: Text(appStrings.createClassTitle),
      ),
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
    expect(find.text(appStrings.bookingTitle.toUpperCase()), findsOneWidget);
    expect(find.text('COACH · Alma'), findsOneWidget);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking composition fits at 360x800', (tester) async {
    await pumpAt(tester, const Size(360, 800));
    await tester.drag(find.byType(ListView).last, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('MOBILITY'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
