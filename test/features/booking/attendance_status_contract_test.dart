import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Profile query and history accept attended only', () {
    final profile = File(
      'lib/features/profile/presentation/screens/profile_screen.dart',
    ).readAsStringSync();
    expect(profile, contains(".eq('status', 'attended')"));
    expect(profile, contains('confirmedAttendanceRows('));
  });

  test('time passage does not automatically promote booked to attended', () {
    final migrationSources = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.sql'))
        // This migration defines the explicit admin/coach attendance RPCs.
        // Their attended transition is the behavior this contract permits.
        .where(
          (file) => !file.path.endsWith(
            '20260809160000_migrate_attendance_guests_to_effective_gym.sql',
          ),
        )
        .map((file) => file.readAsStringSync().toLowerCase())
        .join('\n');

    expect(
      migrationSources,
      isNot(contains("set status = 'attended'")),
      reason: 'Attendance must remain an explicit admin/coach action.',
    );
  });

  test('Class Detail exposes only the existing attendance statuses', () {
    final detail = File(
      'lib/features/booking/presentation/widgets/class_details_sheet.dart',
    ).readAsStringSync();
    expect(detail, contains("call(booking, 'attended')"));
    expect(detail, contains("call(booking, 'no_show')"));
    expect(detail, contains("_ => appStrings.bookingBooked"));
  });
}
