import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/booking/presentation/widgets/class_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('en'));
  Future<void> pumpView(
    WidgetTester tester, {
    required bool admin,
    ThemeMode mode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: Scaffold(
          body: ClassDetailsView(
            klass: {
              'id': 'class-1',
              'title': 'CrossFit',
              'starts_at': DateTime(2026, 8, 13, 10).toIso8601String(),
              'duration_minutes': 60,
              'capacity': 10,
            },
            bookings: const [
              {
                'id': 'member-booking',
                'user_id': 'member-1',
                'is_guest': false,
                'status': 'booked',
              },
              {
                'id': 'guest-booking',
                'guest_name': 'Guest One',
                'is_guest': true,
                'status': 'attended',
              },
            ],
            waitlist: const [],
            profilesById: const {
              'member-1': {'full_name': 'Member One'},
            },
            actionLabel: 'Reservar',
            onAction: null,
            onBack: () {},
            attendeeActions: admin
                ? ClassDetailAttendeeActions(
                    onAddMember: (_) async => null,
                    onAddGuest: (_) async => null,
                  )
                : null,
            onAttendeeStatusChanged: (_, _) async {},
            onAttendeeRemoved: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('admin sees direct member actions with real statuses', (
    tester,
  ) async {
    await pumpView(tester, admin: true);
    expect(
      find.byKey(const ValueKey('class-attendee-member-booking')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('class-attendee-guest-booking')),
      findsOneWidget,
    );
    expect(find.text(appStrings.bookingBooked), findsOneWidget);
    expect(find.text(appStrings.attended), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('class-attendee-member-booking')),
    );
    await tester.pumpAndSettle();
    expect(find.text(appStrings.markAttendance.toUpperCase()), findsOneWidget);
    expect(find.text(appStrings.markNoShow.toUpperCase()), findsOneWidget);
    expect(find.text(appStrings.remove.toUpperCase()), findsOneWidget);
  });

  testWidgets('athlete has no attendee action in dark at 320px', (
    tester,
  ) async {
    await pumpView(tester, admin: false, mode: ThemeMode.dark);
    expect(
      find.byKey(const ValueKey('class-attendee-member-booking')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
