import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/widgets/app_admin_actions.dart';
import 'package:ath615v2/core/widgets/app_week_date_selector.dart';
import 'package:ath615v2/core/widgets/app_secondary_action_header.dart';
import 'package:ath615v2/features/booking/presentation/widgets/booking_day_chips.dart';
import 'package:ath615v2/features/workouts/presentation/screens/workouts_screen.dart';
import 'package:ath615v2/features/workouts/presentation/widgets/workout_card.dart';
import 'package:ath615v2/features/workouts/presentation/widgets/workout_form_controls.dart';
import 'package:ath615v2/features/workouts/presentation/widgets/workouts_header.dart';
import 'package:ath615v2/core/widgets/app_detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
    await initializeDateFormatting('en');
  });

  Widget workoutRow({required String id, required String program}) {
    return WorkoutCard(
      workoutId: id,
      program: program,
      description: 'FOR TIME\n10-9-8 pull-ups\n20 double unders',
      date: '12/08/2030',
      likes: const [
        {'user_id': 'athlete-1'},
        {'user_id': 'athlete-2'},
      ],
      comments: const [
        {'id': 'comment-1'},
      ],
    );
  }

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    required Widget header,
    int rows = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              header,
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  children: List.generate(
                    rows,
                    (index) => workoutRow(
                      id: 'workout-$index',
                      program: index == 0 ? 'Operation LFG' : 'Cross Training',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Finder commentCount(String workoutId, int count) => find.descendant(
    of: find.byKey(ValueKey('workout-comment-count-$workoutId')),
    matching: find.text('$count'),
  );

  testWidgets('comment count always renders the workout-specific total', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              WorkoutCard(
                workoutId: 'zero',
                program: 'Operation LFG',
                description: 'WOD A',
                date: '13/08/2030',
                likes: const [],
                comments: const [],
              ),
              WorkoutCard(
                workoutId: 'one',
                program: 'CrossFit',
                description: 'WOD B',
                date: '13/08/2030',
                likes: const [],
                comments: const [
                  {'id': 'comment-1'},
                ],
              ),
              WorkoutCard(
                workoutId: 'many',
                program: 'Hyrox',
                description: 'WOD C',
                date: '13/08/2030',
                likes: const [],
                comments: const [
                  {'id': 'comment-2'},
                  {'id': 'comment-3'},
                  {'id': 'comment-4'},
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(commentCount('zero', 0), findsOneWidget);
    expect(commentCount('one', 1), findsOneWidget);
    expect(commentCount('many', 3), findsOneWidget);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'comment count follows refreshed card data at 320px in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Future<void> pumpComments(int count) => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            home: Scaffold(
              body: WorkoutCard(
                workoutId: 'refresh',
                program: 'CrossFit',
                description: 'FOR TIME',
                date: '13/08/2030',
                likes: const [],
                comments: List.generate(
                  count,
                  (index) => {'id': 'comment-$index'},
                ),
              ),
            ),
          ),
        );

        await pumpComments(2);
        expect(commentCount('refresh', 2), findsOneWidget);

        await pumpComments(3);
        expect(commentCount('refresh', 3), findsOneWidget);

        await pumpComments(1);
        expect(commentCount('refresh', 1), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('WOD composition fits at 390x844 with interactions', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(390, 844),
      header: WorkoutsHeader(
        gymName: 'ATHLETE 615',
        canManage: true,
        onPrograms: () {},
        unreadNotifications: 0,
        onOpenNotifications: () {},
      ),
    );
    expect(find.text('OPERATION LFG'), findsOneWidget);
    expect(find.textContaining('FOR TIME'), findsOneWidget);
    expect(find.byTooltip('1 comment'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(find.text(appStrings.workoutLogResult), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workout section renders every content line without navigation', (
    tester,
  ) async {
    const longBody =
        'LINE 01\nLINE 02\nLINE 03\nLINE 04\nLINE 05\nLINE 06\n'
        'LINE 07\nLINE 08\nLINE 09\nLINE 10\nLINE 11\nLINE 12';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkoutCard(
              workoutId: 'full-wod',
              program: 'CrossFit',
              description: longBody,
              date: '13/08/2030',
              likes: const [],
              comments: const [],
            ),
          ),
        ),
      ),
    );

    final body = tester.widget<Text>(
      find.byKey(const ValueKey('workout-body-full-wod')),
    );
    expect(body.data, longBody);
    expect(body.maxLines, isNull);
    expect(body.overflow, isNull);
    expect(find.byType(InkWell), findsWidgets);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(
      find.byKey(const ValueKey('workout-log-result-full-wod')),
      findsOneWidget,
    );
  });

  testWidgets('Booking and WOD calendars consume the same visual widget', (
    tester,
  ) async {
    final today = DateTime(2030, 8, 13);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Column(
          children: [
            BookingDayChips(selectedDay: today, onSelected: (_) {}),
            WorkoutWeekCalendar(
              weekStart: DateTime(2030, 8, 12),
              selectedDate: today,
              locale: 'en',
              onSelected: (_) {},
              onPreviousWeek: () {},
              onNextWeek: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.byType(AppWeekDateSelector), findsNWidgets(2));
    for (final selector in tester.widgetList<SizedBox>(
      find.descendant(
        of: find.byType(AppWeekDateSelector),
        matching: find.byType(SizedBox),
      ),
    )) {
      if (selector.key == const ValueKey('app-week-date-selector')) {
        expect(selector.height, 72);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('workout admin pencil uses shared outlined action sheet', (
    tester,
  ) async {
    await pumpAt(tester, const Size(320, 720), header: const SizedBox.shrink());
    // Re-pump a manageable row because the helper's row is athlete-facing.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: WorkoutCard(
            workoutId: 'admin-wod',
            program: 'CrossFit',
            description: 'FOR TIME',
            date: '13/08/2030',
            likes: const [],
            comments: const [],
            canManage: true,
            useEditAction: true,
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AppOutlinedAdminButton));
    await tester.pumpAndSettle();
    expect(find.byType(AppAdminActionSheet), findsOneWidget);
    expect(find.textContaining('EDIT'), findsOneWidget);
    expect(find.textContaining('DELETE'), findsOneWidget);
  });

  testWidgets('detail header and back action fit at 360x800', (tester) async {
    var backed = false;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppDetailHeader(title: 'WOD', onBack: () => backed = true),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    expect(backed, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'empty workout detail header aligns back and admin in ${mode.name}',
      (tester) async {
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
              body: SafeArea(
                child: AppSecondaryActionHeader(
                  onBack: () {},
                  action: AppOutlinedAdminButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit WOD',
                    onPressed: () {},
                    accentColor: const Color(0xFF159ED1),
                  ),
                ),
              ),
            ),
          ),
        );

        final back = tester.getCenter(
          find.byKey(const ValueKey('secondary-header-back')),
        );
        final edit = tester.getCenter(find.byType(AppOutlinedAdminButton));
        expect(back.dy, edit.dy);
        expect(find.text('OPERATION LFG'), findsNothing);
        final backIcon = tester.widget<Icon>(
          find.byIcon(Icons.arrow_back_ios_new_rounded),
        );
        expect(backIcon.color, isNot(const Color(0xFFB59B6A)));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('shared workout form controls fit a narrow mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const WorkoutFormSectionLabel(label: 'PROGRAM'),
                    const SizedBox(height: 8),
                    WorkoutFormActionRow(
                      icon: Icons.calendar_month_outlined,
                      title: 'Date',
                      subtitle: '12/08/2030',
                      onTap: () {},
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      minLines: 4,
                      maxLines: 4,
                      decoration: workoutDescriptionInput(
                        context,
                        hintText: 'Write the WOD...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    WorkoutFormButton(
                      label: 'Create workout',
                      loading: false,
                      enabled: true,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('shared create/edit workout form fits 320px in ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController(
        text: 'AMRAP 20\n10 pull-ups\n20 double unders',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: WorkoutFormScaffold(
            title: 'Edit WOD',
            onClose: () {},
            submit: WorkoutFormButton(
              label: 'Save changes',
              loading: false,
              enabled: true,
              onPressed: () {},
            ),
            children: [
              WorkoutFormFields(
                loadingPrograms: false,
                programs: const [
                  {
                    'id': 'crossfit',
                    'name': 'CrossFit With A Very Long Program Name',
                  },
                ],
                programId: 'crossfit',
                onProgramChanged: (_) {},
                dateLabel: '13/08/2030',
                onDateTap: () {},
                imageTitle: 'Change image',
                imageSubtitle: 'Current image',
                onImageTap: () {},
                imagePreview: Container(height: 170, color: Colors.black12),
                descriptionController: controller,
              ),
            ],
          ),
        ),
      );

      expect(find.byKey(const ValueKey('workout-form-header')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workout-program-field')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('workout-date-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('workout-image-field')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workout-content-field')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('workout-form-submit')), findsOneWidget);
      expect(
        find.text('AMRAP 20\n10 pull-ups\n20 double unders'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
