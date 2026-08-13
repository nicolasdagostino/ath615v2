import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_selected_date_label.dart';
import 'package:ath615v2/core/widgets/app_calendar_date_picker_sheet.dart';
import 'package:ath615v2/features/workouts/data/workouts_date_data_source.dart';
import 'package:ath615v2/features/workouts/presentation/screens/workouts_screen.dart';
import 'package:ath615v2/features/workouts/presentation/widgets/workout_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeDateSource implements WorkoutsDateDataSource {
  _FakeDateSource({required this.role, required this.rowsByDate});

  final String role;
  final Map<String, List<Map<String, dynamic>>> rowsByDate;
  final List<String> requestedDates = [];

  @override
  Future<WorkoutViewerContext> loadViewer() async =>
      WorkoutViewerContext(role: role, gymId: 'gym-1', isAccountActive: true);

  @override
  Future<List<Map<String, dynamic>>> loadForDate({
    required String gymId,
    required DateTime date,
  }) async {
    final key = _key(date);
    requestedDates.add(key);
    return rowsByDate[key] ?? [];
  }

  String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _workout({
  required String id,
  required String date,
  required String programId,
  required String program,
}) => {
  'id': id,
  'workout_date': date,
  'description': 'AMRAP x 5 minutes\n10 pull-ups\n20 double unders',
  'image_url': null,
  'program_id': programId,
  'programs': {'name': program},
  'workout_likes': <Map<String, dynamic>>[],
  'workout_comments': <Map<String, dynamic>>[],
};

void main() {
  const today = '2030-08-13';
  final now = DateTime(2030, 8, 13, 12);

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeDateSource source, {
    ThemeMode mode = ThemeMode.light,
    Size size = const Size(320, 720),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: WorkoutsScreen(
          gymName: 'ATHLETE615',
          unreadNotifications: 0,
          onOpenNotifications: () {},
          dataSource: source,
          nowForTesting: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('calendar and today workout fit 320px in ${mode.name}', (
      tester,
    ) async {
      final source = _FakeDateSource(
        role: 'athlete',
        rowsByDate: {
          today: [
            _workout(
              id: 'today',
              date: today,
              programId: 'crossfit',
              program: 'CrossFit With A Long Program Name',
            ),
          ],
        },
      );
      await pumpScreen(tester, source, mode: mode);

      expect(find.byType(WorkoutWeekCalendar), findsOneWidget);
      expect(find.text('ATHLETE615'), findsOneWidget);
      expect(find.byKey(const ValueKey('workout-gym-header')), findsOneWidget);
      expect(find.text(appStrings.workoutsTitle), findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
      expect(find.byKey(const ValueKey('workout-header-create')), findsNothing);
      expect(find.text('MON'), findsOneWidget);
      expect(find.text('TUE'), findsOneWidget);
      expect(find.text('WED'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workout-selected-date-label')),
        findsOneWidget,
      );
      expect(find.text('TUESDAY, 13 AUGUST 2030'), findsOneWidget);
      expect(find.byType(AppSelectedDateLabel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workout-open-month-calendar')),
        findsOneWidget,
      );
      expect(find.byType(WorkoutCard), findsOneWidget);
      expect(find.textContaining('CROSSFIT WITH'), findsOneWidget);
      expect(find.text('13/08/2030'), findsNothing);
      expect(source.requestedDates, [today]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('athlete navigates history but never queries future workouts', (
    tester,
  ) async {
    final source = _FakeDateSource(
      role: 'athlete',
      rowsByDate: {
        '2030-08-12': [
          _workout(
            id: 'past',
            date: '2030-08-12',
            programId: 'lfg',
            program: 'Operation LFG',
          ),
        ],
        '2030-08-14': [
          _workout(
            id: 'secret-future',
            date: '2030-08-14',
            programId: 'secret',
            program: 'Secret Program',
          ),
        ],
      },
    );
    await pumpScreen(tester, source);

    await tester.tap(find.byKey(const ValueKey('workout-day-2030-08-12')));
    await tester.pumpAndSettle();
    expect(find.text('OPERATION LFG'), findsOneWidget);
    expect(source.requestedDates, contains('2030-08-12'));

    await tester.tap(find.byKey(const ValueKey('workout-day-2030-08-14')));
    await tester.pumpAndSettle();
    expect(find.text('SECRET PROGRAM'), findsNothing);
    expect(source.requestedDates, isNot(contains('2030-08-14')));
    expect(find.byKey(const ValueKey('workout-empty-state')), findsOneWidget);
  });

  testWidgets('coach also never queries future workouts', (tester) async {
    final source = _FakeDateSource(
      role: 'coach',
      rowsByDate: {
        '2030-08-14': [
          _workout(
            id: 'future-coach',
            date: '2030-08-14',
            programId: 'coach-only',
            program: 'Hidden Future',
          ),
        ],
      },
    );
    await pumpScreen(tester, source);
    await tester.tap(find.byKey(const ValueKey('workout-day-2030-08-14')));
    await tester.pumpAndSettle();

    expect(source.requestedDates, isNot(contains('2030-08-14')));
    expect(find.text('HIDDEN FUTURE'), findsNothing);
  });

  testWidgets('admin sees future workouts and one contextual action island', (
    tester,
  ) async {
    final source = _FakeDateSource(
      role: 'admin',
      rowsByDate: {
        '2030-08-14': [
          _workout(
            id: 'future',
            date: '2030-08-14',
            programId: 'crossfit',
            program: 'CrossFit',
          ),
        ],
      },
    );
    await pumpScreen(tester, source);

    expect(find.byKey(const ValueKey('workout-programs')), findsOneWidget);
    expect(find.byKey(const ValueKey('workout-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('workout-admin-island')), findsOneWidget);
    expect(find.byKey(const ValueKey('workout-header-create')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('workout-programs'))),
      const Size(52, 52),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('workout-create'))),
      const Size(52, 52),
    );
    await tester.tap(find.byKey(const ValueKey('workout-day-2030-08-14')));
    await tester.pumpAndSettle();
    expect(find.text('CROSSFIT'), findsOneWidget);
    expect(source.requestedDates, contains('2030-08-14'));
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workout-day-2030-08-15')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workout-empty-state')), findsOneWidget);
    expect(find.text(appStrings.workoutCreate.toUpperCase()), findsNothing);
    expect(find.byKey(const ValueKey('workout-create')), findsOneWidget);
  });

  testWidgets('athlete has no admin island or header actions', (tester) async {
    final source = _FakeDateSource(role: 'athlete', rowsByDate: const {});
    await pumpScreen(tester, source);

    expect(find.byKey(const ValueKey('workout-admin-island')), findsNothing);
    expect(find.byKey(const ValueKey('workout-programs')), findsNothing);
    expect(find.byKey(const ValueKey('workout-create')), findsNothing);
  });

  testWidgets('month calendar jumps selected date and visible week', (
    tester,
  ) async {
    final source = _FakeDateSource(
      role: 'admin',
      rowsByDate: {
        '2030-09-27': [
          _workout(
            id: 'september',
            date: '2030-09-27',
            programId: 'hyrox',
            program: 'Hyrox September',
          ),
        ],
      },
    );
    await pumpScreen(tester, source);

    await tester.tap(find.byKey(const ValueKey('workout-open-month-calendar')));
    await tester.pumpAndSettle();
    expect(find.byType(AppCalendarDatePickerSheet), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('27').last);
    await tester.pumpAndSettle();

    expect(source.requestedDates, contains('2030-09-27'));
    expect(
      find.byKey(const ValueKey('workout-day-2030-09-27')),
      findsOneWidget,
    );
    expect(find.text('FRIDAY, 27 SEPTEMBER 2030'), findsOneWidget);
    expect(find.text('HYROX SEPTEMBER'), findsOneWidget);
  });

  testWidgets('manual weekly swipe remains available', (tester) async {
    final source = _FakeDateSource(role: 'athlete', rowsByDate: const {});
    await pumpScreen(tester, source);

    expect(
      find.byKey(const ValueKey('workout-day-2030-08-12')),
      findsOneWidget,
    );
    await tester.fling(
      find.byKey(const ValueKey('workout-week-calendar')),
      const Offset(-240, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('workout-day-2030-08-19')),
      findsOneWidget,
    );
  });

  testWidgets('multiple programs on one date render every workout vertically', (
    tester,
  ) async {
    final source = _FakeDateSource(
      role: 'athlete',
      rowsByDate: {
        today: [
          _workout(
            id: 'one',
            date: today,
            programId: 'crossfit',
            program: 'CrossFit',
          ),
          _workout(
            id: 'three',
            date: today,
            programId: 'hyrox',
            program: 'Hyrox',
          ),
          _workout(
            id: 'two',
            date: today,
            programId: 'lfg',
            program: 'Operation LFG',
          ),
        ],
      },
    );
    await pumpScreen(tester, source);

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(WorkoutCard), findsNWidgets(3));
    expect(find.text('CROSSFIT'), findsOneWidget);
    expect(find.text('OPERATION LFG'), findsOneWidget);
    expect(find.text('HYROX'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('selected historical date survives a pushed detail route', (
    tester,
  ) async {
    final source = _FakeDateSource(role: 'athlete', rowsByDate: const {});
    await pumpScreen(tester, source);
    await tester.tap(find.byKey(const ValueKey('workout-day-2030-08-12')));
    await tester.pumpAndSettle();
    final selectedBefore = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('workout-day-2030-08-12')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (selectedBefore.decoration as BoxDecoration).color,
      isNot(Colors.transparent),
    );

    final context = tester.element(find.byType(WorkoutsScreen));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Detail'))).pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workout-day-2030-08-12')),
      findsOneWidget,
    );
  });
}
