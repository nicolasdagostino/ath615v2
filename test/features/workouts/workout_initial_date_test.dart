import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/workouts/data/workouts_date_data_source.dart';
import 'package:ath615v2/features/workouts/presentation/screens/workouts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

class _RecordingWorkoutsDataSource implements WorkoutsDateDataSource {
  DateTime? requestedDate;

  @override
  Future<WorkoutViewerContext> loadViewer() async => const WorkoutViewerContext(
    role: 'admin',
    gymId: 'gym-1',
    isAccountActive: true,
  );

  @override
  Future<List<Map<String, dynamic>>> loadForDate({
    required String gymId,
    required DateTime date,
  }) async {
    requestedDate = date;
    return const [];
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('en');
  });

  testWidgets('initial date selects its day and containing week', (
    tester,
  ) async {
    final source = _RecordingWorkoutsDataSource();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: WorkoutsScreen(
          gymName: 'Athlete 615',
          unreadNotifications: 0,
          onOpenNotifications: () {},
          dataSource: source,
          nowForTesting: DateTime(2026, 8, 14),
          initialDate: DateTime(2026, 8, 13),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(source.requestedDate, DateTime(2026, 8, 13));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('app-selected-day')),
        matching: find.text('13'),
      ),
      findsOneWidget,
    );
  });
}
