import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/booking/presentation/screens/booking_screen.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_class_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  List<Map<String, dynamic>> profiles(int count) => [
    for (var index = 0; index < count; index++)
      {
        'id': 'athlete-$index',
        'full_name': 'Athlete $index',
        'avatar_url': null,
      },
  ];

  Widget card({required int profileCount, VoidCallback? action}) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: BookingClassCard(
        klass: const {
          'title': 'Cross Training With A Long Class Name',
          'starts_at': '2030-08-12T07:30:00Z',
        },
        bookedCount: profileCount,
        capacity: 10,
        bookedProfiles: profiles(profileCount),
        buttonLabel: appStrings.bookingBook,
        buttonAction: action,
        onTap: () {},
        formatDateTime: (raw) => raw,
      ),
    ),
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required int count,
    VoidCallback? action,
  }) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(card(profileCount: count, action: action));
    await tester.pump();
  }

  testWidgets('zero bookings leaves no avatar stack', (tester) async {
    await pumpCard(tester, count: 0);
    expect(find.byKey(const ValueKey('booking-avatar-stack')), findsNothing);
    expect(find.textContaining('0 / 10'), findsOneWidget);
  });

  testWidgets('one booking shows one fallback avatar', (tester) async {
    await pumpCard(tester, count: 1);
    expect(find.byKey(const ValueKey('booking-avatar-stack')), findsOneWidget);
    expect(find.byKey(const ValueKey('booking-avatar-athlete-0')), findsOne);
    expect(find.byKey(const ValueKey('booking-avatar-fallback')), findsOne);
    expect(find.text('+1'), findsNothing);
  });

  testWidgets('four bookings show four avatars without overflow count', (
    tester,
  ) async {
    await pumpCard(tester, count: 4);
    expect(
      find.byKey(const ValueKey('booking-avatar-fallback')),
      findsNWidgets(4),
    );
    expect(find.byKey(const ValueKey('booking-avatar-overflow')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('six bookings show four avatars and plus two without overflow', (
    tester,
  ) async {
    await pumpCard(tester, count: 6);
    expect(
      find.byKey(const ValueKey('booking-avatar-fallback')),
      findsNWidgets(4),
    );
    expect(find.text('+2'), findsOneWidget);
    expect(find.textContaining('6 / 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar stack does not change the booking action', (
    tester,
  ) async {
    var tapped = false;
    await pumpCard(tester, count: 6, action: () => tapped = true);
    await tester.tap(find.text(appStrings.bookingBook.toUpperCase()));
    await tester.pump();
    expect(tapped, isTrue);
  });

  test('only booked profiles enter the stack; waitlist is not an input', () {
    final rows = bookingActiveProfilesByClass(
      bookings: const [
        {'class_id': 'class-1', 'user_id': 'booked', 'status': 'booked'},
        {'class_id': 'class-1', 'user_id': 'cancelled', 'status': 'cancelled'},
        {'class_id': 'class-1', 'user_id': 'no-show', 'status': 'no_show'},
      ],
      profilesById: {
        'booked': {'id': 'booked'},
        'cancelled': {'id': 'cancelled'},
        'no-show': {'id': 'no-show'},
        'waitlisted': {'id': 'waitlisted'},
      },
    );

    expect(rows['class-1'], [
      const {'id': 'booked'},
    ]);
  });
}
