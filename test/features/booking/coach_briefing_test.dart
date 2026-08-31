import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/theme/app_colors.dart';
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
  int setAttendanceCalls = 0;
  int markAllCalls = 0;

  @override
  Future<CoachBriefing> loadToday() async {
    loadCalls++;
    if (loadError case final error?) throw error;
    return briefing;
  }

  @override
  Future<int> markAllAttended(String classId) async {
    markAllCalls++;
    return 2;
  }

  @override
  Future<bool> setAttendance({
    required String bookingId,
    required String expectedStatus,
    required String status,
  }) async {
    setAttendanceCalls++;
    return true;
  }
}

CoachBriefingAthlete athlete({
  String id = 'booking-1',
  String status = 'booked',
  bool firstClass = false,
  bool usable = true,
  String? planType = 'class_pack',
  int? credits = 4,
  DateTime? expiresAt,
}) => CoachBriefingAthlete(
  bookingId: id,
  userId: 'member-$id',
  name: 'Athlete $id',
  avatarUrl: null,
  isGuest: false,
  attendanceStatus: status,
  firstClass: firstClass,
  membershipUsable: usable,
  membershipPlanType: planType,
  creditsRemaining: credits,
  membershipExpiresAt: expiresAt,
);

CoachBriefingClass klass({
  required String id,
  required DateTime startsAt,
  String localStartTime = '12:00',
  int duration = 60,
  List<CoachBriefingAthlete>? booked,
  List<CoachBriefingWaitlistMember> waitlist = const [],
  String? wod = '5 rounds\n10 pull-ups\n15 squats',
}) => CoachBriefingClass(
  id: id,
  title: 'CrossFit $id',
  startsAt: startsAt,
  localStartTime: localStartTime,
  durationMinutes: duration,
  capacity: 16,
  coachName: 'Coach Alex',
  programName: 'CrossFit',
  workoutDescription: wod,
  booked: booked ?? [athlete()],
  waitlist: waitlist,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });

  final now = DateTime.utc(2026, 8, 31, 10);

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
    expect(
      find.byKey(const ValueKey('app-primary-gym-header')),
      findsOneWidget,
    );
  });

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
        expiresAt: now.subtract(const Duration(minutes: 1)),
      ).membershipExpiresWithin(now, const Duration(days: 7)),
      isFalse,
    );
    expect(
      athlete(
        usable: false,
        expiresAt: now.add(const Duration(days: 2)),
      ).membershipExpiresWithin(now, const Duration(days: 7)),
      isFalse,
    );
  });

  testWidgets(
    'today is chronological, timezone-aware and shows status, occupancy and waitlist',
    (tester) async {
      final repository = _FakeCoachBriefingRepository(
        CoachBriefing(
          localDate: DateTime(2026, 8, 31),
          timezone: 'Europe/Madrid',
          classes: [
            klass(
              id: 'completed',
              startsAt: now.subtract(const Duration(hours: 2)),
            ),
            klass(
              id: 'progress',
              startsAt: now.subtract(const Duration(minutes: 30)),
              waitlist: const [
                CoachBriefingWaitlistMember(
                  userId: 'wait-1',
                  name: 'Waiting Athlete',
                  avatarUrl: null,
                  position: 1,
                ),
              ],
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
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('UPCOMING'), findsOneWidget);
      expect(find.text('1 / 16'), findsNWidgets(3));
      expect(find.text('WAITLIST 1'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('CrossFit completed')).dy,
        lessThan(tester.getTopLeft(find.text('CrossFit progress')).dy),
      );
      expect(repository.loadCalls, 1);
    },
  );

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
    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('secret_rpc'), findsNothing);
  });

  testWidgets(
    'class view shows WOD, indicators, waitlist, member navigation and attendance',
    (tester) async {
      String? openedMember;
      final repository = _FakeCoachBriefingRepository(
        CoachBriefing(
          localDate: DateTime(2026, 8, 31),
          timezone: 'Europe/Madrid',
          classes: [
            klass(
              id: 'live',
              startsAt: now.subtract(const Duration(minutes: 10)),
              booked: [
                athlete(
                  firstClass: true,
                  credits: 2,
                  expiresAt: now.add(const Duration(days: 2)),
                ),
                athlete(id: 'booking-2', usable: false),
                athlete(id: 'booking-3'),
              ],
              waitlist: const [
                CoachBriefingWaitlistMember(
                  userId: 'wait-1',
                  name: 'Waiting Athlete',
                  avatarUrl: null,
                  position: 1,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CoachBriefingScreen(
            repository: repository,
            now: () => now,
            onOpenMember: (id) => openedMember = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coach-class-live')));
      await tester.pumpAndSettle();

      expect(find.textContaining('5 rounds'), findsOneWidget);
      expect(find.text('FIRST CLASS'), findsOneWidget);
      expect(find.text('LOW CREDITS'), findsOneWidget);
      expect(find.text('EXPIRING'), findsOneWidget);
      expect(find.text('NO MEMBERSHIP'), findsOneWidget);

      await tester.tap(find.text('Athlete booking-1'));
      expect(openedMember, 'member-booking-1');
      await tester.tap(find.byKey(const ValueKey('coach-attended-booking-1')));
      await tester.pump();
      expect(repository.setAttendanceCalls, 1);
      await tester.tap(find.byKey(const ValueKey('coach-no-show-booking-2')));
      await tester.pump();
      expect(repository.setAttendanceCalls, 2);

      await tester.tap(find.byKey(const ValueKey('coach-mark-all-attended')));
      await tester.pump();
      expect(repository.markAllCalls, 1);
      expect(repository.setAttendanceCalls, 2);

      await tester.scrollUntilVisible(
        find.text('Waiting Athlete'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('WAITLIST · 1'), findsOneWidget);
      expect(find.text('Waiting Athlete'), findsOneWidget);
    },
  );

  testWidgets('class view has discreet empty WOD and bookings states', (
    tester,
  ) async {
    final repository = _FakeCoachBriefingRepository(
      CoachBriefing(
        localDate: DateTime(2026, 8, 31),
        timezone: 'Europe/Madrid',
        classes: [
          klass(id: 'empty', startsAt: now, booked: const [], wod: null),
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
    await tester.tap(find.byKey(const ValueKey('coach-class-empty')));
    await tester.pumpAndSettle();
    expect(find.text('No WOD added for this class.'), findsOneWidget);
    expect(find.text('No athletes booked yet.'), findsOneWidget);
    expect(find.textContaining('WAITLIST'), findsNothing);
  });
}
