import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_detail_header.dart';
import 'package:ath615v2/features/booking/data/my_reservations_data_source.dart';
import 'package:ath615v2/features/booking/presentation/screens/my_reservations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeReservationsSource implements MyReservationsDataSource {
  _FakeReservationsSource({this.upcoming = const [], this.history = const []});

  final List<Map<String, dynamic>> upcoming;
  final List<Map<String, dynamic>> history;
  final List<int> historyOffsets = [];

  @override
  Future<List<Map<String, dynamic>>> loadUpcoming() async => upcoming;

  @override
  Future<List<Map<String, dynamic>>> loadHistory({
    required int offset,
    int limit = bookingHistoryPageSize,
  }) async {
    historyOffsets.add(offset);
    return history.skip(offset).take(limit).toList();
  }
}

Map<String, dynamic> reservation(
  int index, {
  String kind = 'booking',
  String status = 'booked',
  bool future = true,
}) => {
  'id': 'class-$index',
  'title': 'Technique $index',
  'starts_at': DateTime.now()
      .add(Duration(days: future ? index + 1 : -(index + 1)))
      .toUtc()
      .toIso8601String(),
  'duration_minutes': 60,
  'capacity': 16,
  'programs': {'name': index.isEven ? 'CrossFit' : 'Hyrox'},
  'coach': {'full_name': 'Coach Alex'},
  'reservation_kind': kind,
  'reservation_status': status,
  if (kind == 'waitlist') 'waitlist_position': 3,
};

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  Future<void> pump(
    WidgetTester tester,
    _FakeReservationsSource source, {
    ValueChanged<Map<String, dynamic>>? onOpen,
  }) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MyReservationsScreen(
          dataSource: source,
          onOpenForTesting: onOpen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('upcoming combines reserved and real waitlist position', (
    tester,
  ) async {
    Map<String, dynamic>? opened;
    final source = _FakeReservationsSource(
      upcoming: [
        reservation(0),
        reservation(1, kind: 'waitlist'),
      ],
    );
    await pump(tester, source, onOpen: (row) => opened = row);

    expect(find.text(appStrings.reserved.toUpperCase()), findsOne);
    expect(find.text('${appStrings.waitlist.toUpperCase()} · #3'), findsOne);
    expect(find.text('CROSSFIT'), findsOne);
    await tester.tap(find.text('CROSSFIT'));
    expect(opened?['id'], 'class-0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('header owns the top safe area on notched devices', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(() => tester.view.padding = FakeViewPadding.zero);

    await pump(tester, _FakeReservationsSource());

    final header = find.byType(AppDetailHeader);
    expect(header, findsOneWidget);
    expect(tester.getTopLeft(header).dy, 0);
    expect(tester.getSize(header).width, 320);
    expect(
      tester.getTopLeft(find.byIcon(Icons.arrow_back_ios_new_rounded)).dy,
      greaterThanOrEqualTo(47),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new_rounded)).color,
      AppColors.primary,
    );

    await tester.tap(find.byKey(const ValueKey('reservations-history-chip')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, 0);
    expect(tester.getSize(header).width, 320);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new_rounded)).color,
      AppColors.primary,
    );
  });

  testWidgets('upcoming and history have distinct empty states', (
    tester,
  ) async {
    await pump(tester, _FakeReservationsSource());
    expect(find.text(appStrings.noUpcomingBookings), findsOne);
    await tester.tap(find.byKey(const ValueKey('reservations-history-chip')));
    await tester.pumpAndSettle();
    expect(find.text(appStrings.noBookingHistory), findsOne);
  });

  testWidgets('history paginates 15 rows and keeps real statuses', (
    tester,
  ) async {
    final source = _FakeReservationsSource(
      history: List.generate(
        20,
        (index) => reservation(
          index,
          future: false,
          status: index == 0 ? 'no_show' : 'attended',
        ),
      ),
    );
    await pump(tester, source);
    await tester.tap(find.byKey(const ValueKey('reservations-history-chip')));
    await tester.pumpAndSettle();

    expect(source.historyOffsets, [0]);
    expect(find.text(appStrings.noShow.toUpperCase()), findsOne);
    await tester.fling(
      find.byKey(const ValueKey('booking-history-list')),
      const Offset(0, -2600),
      4000,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('booking-history-load-more')), findsOne);
    await tester.tap(find.byKey(const ValueKey('booking-history-load-more')));
    await tester.pumpAndSettle();
    expect(source.historyOffsets, [0, bookingHistoryPageSize]);
    expect(
      find.byKey(const ValueKey('booking-history-load-more')),
      findsNothing,
    );
  });
}
