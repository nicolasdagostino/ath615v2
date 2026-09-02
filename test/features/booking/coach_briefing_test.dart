import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/booking/data/coach_briefing_repository.dart';
import 'package:ath615v2/features/booking/presentation/screens/coach_briefing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeCoachBriefingRepository implements CoachBriefingRepository {
  _FakeCoachBriefingRepository(this.briefing, {this.loadError});

  final CoachBriefing briefing;
  final Object? loadError;
  int loadCalls = 0;

  @override
  Future<CoachBriefing> loadToday() async {
    loadCalls++;
    if (loadError case final error?) throw error;
    return briefing;
  }

  @override
  Future<int> markAllAttended(String classId) async => 2;

  @override
  Future<bool> setAttendance({
    required String bookingId,
    required String expectedStatus,
    required String status,
  }) async => true;
}

CoachBriefingAthlete athlete({
  int? credits = 4,
  bool usable = true,
  String? planType = 'class_pack',
  DateTime? expiresAt,
}) => CoachBriefingAthlete(
  bookingId: 'booking-1',
  userId: 'member-1',
  name: 'Athlete One',
  avatarUrl: null,
  isGuest: false,
  attendanceStatus: 'booked',
  firstClass: false,
  membershipUsable: usable,
  membershipPlanType: planType,
  creditsRemaining: credits,
  membershipExpiresAt: expiresAt,
);

CoachBriefingClass klass({required String id, required DateTime startsAt}) =>
    CoachBriefingClass(
      id: id,
      title: 'CrossFit $id',
      startsAt: startsAt,
      localStartTime: '12:00',
      durationMinutes: 60,
      capacity: 16,
      coachId: 'coach-1',
      coachName: 'Coach Alex',
      coachAvatarUrl: 'https://example.com/coach.jpg',
      programName: 'CrossFit',
      workoutDescription: '5 rounds',
      booked: [athlete()],
      waitlist: const [],
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });

  final now = DateTime.utc(2026, 8, 31, 10);

  test('class status follows the real start/end window', () {
    expect(
      klass(
        id: 'future',
        startsAt: now.add(const Duration(minutes: 1)),
      ).temporalStatusAt(now),
      CoachClassTemporalStatus.upcoming,
    );
    expect(
      klass(
        id: 'live',
        startsAt: now.subtract(const Duration(minutes: 30)),
      ).temporalStatusAt(now),
      CoachClassTemporalStatus.inProgress,
    );
    expect(
      klass(
        id: 'past',
        startsAt: now.subtract(const Duration(hours: 2)),
      ).temporalStatusAt(now),
      CoachClassTemporalStatus.completed,
    );
  });

  test('membership indicators use only a currently usable membership', () {
    expect(athlete(credits: 2).hasLowCredits, isTrue);
    expect(athlete(credits: 3).hasLowCredits, isFalse);
    expect(athlete(planType: 'unlimited', credits: 1).hasLowCredits, isFalse);
    expect(
      athlete(
        expiresAt: now.add(const Duration(days: 7)),
      ).membershipExpiresWithin(now, const Duration(days: 7)),
      isTrue,
    );
    expect(
      athlete(
        usable: false,
        expiresAt: now.add(const Duration(days: 2)),
      ).membershipExpiresWithin(now, const Duration(days: 7)),
      isFalse,
    );
  });

  testWidgets('today summary stays chronological and has no roster', (
    tester,
  ) async {
    final repository = _FakeCoachBriefingRepository(
      CoachBriefing(
        localDate: DateTime(2026, 8, 31),
        timezone: 'Europe/Madrid',
        classes: [
          klass(
            id: 'completed',
            startsAt: now.subtract(const Duration(hours: 2)),
          ),
          klass(id: 'upcoming', startsAt: now.add(const Duration(hours: 1))),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CoachBriefingScreen(repository: repository, now: () => now),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Europe/Madrid'), findsOneWidget);
    expect(find.textContaining('COMPLETED'), findsOneWidget);
    expect(find.textContaining('UPCOMING'), findsOneWidget);
    expect(find.text('Athlete One'), findsNothing);
    expect(repository.loadCalls, 1);
  });

  testWidgets('blue header owns the status bar safe area and contrast', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CoachBriefingScreen(
          repository: _FakeCoachBriefingRepository(
            CoachBriefing(
              localDate: DateTime(2026, 8, 31),
              timezone: 'Europe/Madrid',
              classes: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarColor, AppColors.primary);
    expect(region.value.statusBarIconBrightness, Brightness.light);
    expect(region.value.statusBarBrightness, Brightness.dark);
  });

  testWidgets('empty day and technical load errors stay human', (tester) async {
    final empty = CoachBriefing(
      localDate: DateTime(2026, 8, 31),
      timezone: 'Europe/Madrid',
      classes: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CoachBriefingScreen(
          repository: _FakeCoachBriefingRepository(empty),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No classes scheduled today.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CoachBriefingScreen(
          key: const ValueKey('error-briefing'),
          repository: _FakeCoachBriefingRepository(
            empty,
            loadError: StateError('PostgrestException P0001 secret_rpc'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't load today's classes. Try again."),
      findsOneWidget,
    );
    expect(find.textContaining('secret_rpc'), findsNothing);
  });
}
