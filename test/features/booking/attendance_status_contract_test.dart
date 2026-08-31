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
          (file) =>
              !file.path.endsWith(
                '20260809160000_migrate_attendance_guests_to_effective_gym.sql',
              ) &&
              !file.path.endsWith(
                '20260826120000_fix_class_notification_timezone_and_batch_attendance.sql',
              ) &&
              !file.path.endsWith(
                '20260831120000_add_daily_coach_briefing.sql',
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

  test('mark-all attendance is server-side, scoped and explicit', () {
    final migration = File(
      'supabase/migrations/20260826120000_fix_class_notification_timezone_and_batch_attendance.sql',
    ).readAsStringSync();
    expect(migration, contains('admin_mark_all_class_attended'));
    expect(migration, contains("cb.status = 'booked'"));
    expect(migration, contains('not coalesce(cb.is_guest, false)'));
    expect(migration, contains("message = 'class_not_started'"));
    expect(migration, contains('public.effective_gym_id()'));
    final sheet = File(
      'lib/features/booking/presentation/widgets/attendance_sheet.dart',
    ).readAsStringSync();
    expect(sheet, contains('markAllClassAttended('));
    expect(sheet, isNot(contains(".update({'status': 'attended'})")));
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
