import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/booking/presentation/widgets/attendance_add_booking_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _harness(Widget child, ThemeMode mode) => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: mode,
  home: Scaffold(body: child),
);

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(320, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_harness(child, mode));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('add member list and empty state fit 320px in ${mode.name}', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        AttendanceAddMemberSheet(
          client: null,
          classId: 'class-1',
          membersLoader: (_) async => const [],
          memberAdder: (_) async => const {},
        ),
        mode: mode,
      );

      expect(find.text('ADD MEMBER'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('attendance-member-search')),
        findsOneWidget,
      );
      expect(find.text('No available members found.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'member search, fallback avatar and selection preserve callbacks',
    (tester) async {
      final queries = <String>[];
      String? addedUserId;
      final members = [
        {
          'user_id': 'member-1',
          'full_name': 'Alex Duarte',
          'email': 'alex@example.com',
          'avatar_url': null,
          'plan_name': 'Unlimited',
          'credits_remaining': 4,
        },
      ];
      await _pumpAt(
        tester,
        AttendanceAddMemberSheet(
          client: null,
          classId: 'class-1',
          membersLoader: (query) async {
            queries.add(query);
            return members;
          },
          memberAdder: (userId) async {
            addedUserId = userId;
            return {'id': 'booking-1', 'user_id': userId};
          },
        ),
      );

      expect(find.text('AD'), findsOneWidget);
      expect(find.text('Alex Duarte'), findsOneWidget);
      expect(find.textContaining('Unlimited'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('attendance-member-search')),
        'Alex',
      );
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pumpAndSettle();
      expect(queries, contains('Alex'));

      await tester.tap(find.text('Alex Duarte'));
      await tester.pumpAndSettle();
      expect(addedUserId, 'member-1');
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('add guest keeps its only real field and CTA in ${mode.name}', (
      tester,
    ) async {
      await _pumpAt(tester, const AttendanceAddGuestSheet(), mode: mode);

      expect(find.text('ADD GUEST'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('attendance-guest-name')),
        findsOneWidget,
      );
      final submitFinder = find.descendant(
        of: find.byKey(const ValueKey('booking-class-form-submit')),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(submitFinder).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('attendance-guest-name')),
        'Guest Athlete',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(submitFinder).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
