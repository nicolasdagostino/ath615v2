import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/features/explore/presentation/widgets/explore_header.dart';
import 'package:ath615v2/features/workouts/presentation/widgets/workout_card.dart';
import 'package:ath615v2/features/workouts/presentation/widgets/workouts_header.dart';
import 'package:ath615v2/core/widgets/app_detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
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
    expect(find.textContaining('1 comment'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Explore rows remain dense at 360x800', (tester) async {
    await pumpAt(
      tester,
      const Size(360, 800),
      rows: 2,
      header: ExploreHeader(
        gymName: 'ATHLETE 615',
        unreadNotifications: 0,
        onOpenNotifications: () {},
      ),
    );
    expect(find.text(appStrings.exploreTitle.toUpperCase()), findsOneWidget);
    expect(find.text('OPERATION LFG'), findsOneWidget);
    expect(find.text('CROSS TRAINING'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
}
