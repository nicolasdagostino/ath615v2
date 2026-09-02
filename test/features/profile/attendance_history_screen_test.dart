import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_detail_header.dart';
import 'package:ath615v2/features/profile/presentation/screens/attendance_history_screen.dart';
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

  Future<void> pumpHistory(
    WidgetTester tester,
    ThemeMode mode,
    List<ProfileAttendance> attendances,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: AttendanceHistoryScreen(attendances: attendances),
      ),
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'attendance history is chronological at 320px in ${mode.name}',
      (tester) async {
        await pumpHistory(tester, mode, [
          ProfileAttendance(
            startsAt: DateTime(2026, 8, 11, 7, 30),
            className: 'Operation LFG',
          ),
          ProfileAttendance(
            startsAt: DateTime(2026, 8, 13, 18),
            className: 'CrossFit',
          ),
        ]);

        expect(find.byType(AppDetailHeader), findsOne);
        expect(find.text('ATTENDANCE'), findsOne);
        expect(find.byType(Divider), findsOne);
        expect(find.text('Attended'), findsNWidgets(2));
        expect(
          tester.getTopLeft(find.text('CrossFit')).dy,
          lessThan(tester.getTopLeft(find.text('Operation LFG')).dy),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('attendance history has a clean empty state', (tester) async {
    await pumpHistory(tester, ThemeMode.light, const []);
    expect(find.byKey(const ValueKey('attendance-history-empty')), findsOne);
    expect(find.byKey(const ValueKey('attendance-history-list')), findsNothing);
  });

  testWidgets('attendance header owns the notched top safe area', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(() => tester.view.padding = FakeViewPadding.zero);
    await pumpHistory(tester, ThemeMode.light, const []);

    final header = find.byType(AppDetailHeader);
    expect(tester.getTopLeft(header).dy, 0);
    expect(
      tester.getTopLeft(find.byIcon(Icons.arrow_back_ios_new_rounded)).dy,
      greaterThanOrEqualTo(47),
    );
  });

  testWidgets('attendance back returns directly to previous profile route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AttendanceHistoryScreen(attendances: []),
              ),
            ),
            child: const Text('PROFILE'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('PROFILE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('PROFILE'), findsOne);
  });
}
