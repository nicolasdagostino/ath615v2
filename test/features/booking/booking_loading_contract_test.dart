import 'dart:io';

import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/widgets/app_centered_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared loading primitive is a clean primary spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppCenteredLoadingIndicator(color: AppColors.primary),
      ),
    );
    final spinner = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('app-centered-loading-indicator')),
    );
    expect(spinner.color, AppColors.primary);
    expect(find.textContaining('Cargando clases'), findsNothing);
  });

  test('Booking and WOD use the same loading primitive', () {
    final booking = File(
      'lib/features/booking/presentation/screens/booking_screen.dart',
    ).readAsStringSync();
    final workout = File(
      'lib/features/workouts/presentation/widgets/workouts_loading_state.dart',
    ).readAsStringSync();
    expect(booking, contains('AppCenteredLoadingIndicator('));
    expect(workout, contains('AppCenteredLoadingIndicator('));
    expect(booking, isNot(contains('message: appStrings.loadingClasses')));
  });

  test('upcoming reservations entry icon uses primary instead of accent', () {
    final booking = File(
      'lib/features/booking/presentation/screens/booking_screen.dart',
    ).readAsStringSync();
    final entryStart = booking.indexOf("ValueKey('booking-my-reservations')");
    final entryEnd = booking.indexOf(
      'const SizedBox(height: AppSpacing.md)',
      entryStart,
    );
    final entry = booking.substring(entryStart, entryEnd);

    expect(entry, contains('color: AppColors.primary'));
    expect(entry, isNot(contains('AppColors.accent')));
  });
}
