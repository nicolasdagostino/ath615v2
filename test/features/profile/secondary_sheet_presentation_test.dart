import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reservations and records reuse the Create Class large sheet', () {
    final booking = File(
      'lib/features/booking/presentation/screens/booking_screen.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/features/profile/presentation/screens/profile_screen.dart',
    ).readAsStringSync();
    final sharedSheet = File(
      'lib/core/widgets/app_large_form_sheet.dart',
    ).readAsStringSync();

    expect(booking, contains('showAppLargeFormSheet<void>('));
    expect(booking, contains('const MyReservationsScreen()'));
    expect(profile, contains('showAppLargeFormSheet<void>('));
    expect(profile, contains('const TrainingScreen(recordsOnly: true)'));
    expect(sharedSheet, contains('appLargeFormSheetHeightFactor = 0.92'));
    expect(sharedSheet, contains("ValueKey('app-large-form-sheet')"));
  });
}
