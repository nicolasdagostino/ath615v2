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

  test('pinned notes remain staff-only and effective-gym scoped', () {
    final migration = File(
      'supabase/migrations/20260825210000_add_member_staff_notes.sql',
    ).readAsStringSync();
    expect(migration, contains('public.member_staff_notes_can_read()'));
    expect(migration, contains('public.membership_actor_is_active()'));
    expect(
      migration,
      contains(
        'public.membership_actor_can_manage() or public.effective_gym_is_coach()',
      ),
    );
    expect(migration, contains('where n.gym_id = v_gym_id and n.is_pinned'));
    expect(migration, contains('gm.gym_id = n.gym_id'));
    expect(
      migration,
      contains('gm.user_id = n.member_user_id and gm.is_active'),
    );
  });

  test('Coach attendance UI depends on an authorized today class match', () {
    final detail = File(
      'lib/features/booking/presentation/widgets/class_details_sheet.dart',
    ).readAsStringSync();
    expect(detail, contains('candidate.id == classId'));
    expect(
      detail,
      contains('operationsRepository != null && intelligence != null'),
    );
    expect(detail, contains('onMarkAllAttended:'));
  });

  test('Dashboard and Booking share the one Class Detail destination', () {
    final booking = File(
      'lib/features/booking/presentation/screens/booking_screen.dart',
    ).readAsStringSync();
    final dashboard = File(
      'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
    ).readAsStringSync();
    expect(booking, contains('showClassDetailsSheet('));
    expect(dashboard, contains('showClassDetailsSheet('));
    expect(dashboard, contains('onOpenTodayClass: _openCoachClass'));
    expect(dashboard, contains('onOpenTodayClassBriefing: _openCoachClass'));
    expect(dashboard, isNot(contains('class _TodayClassBriefingSheet')));
    expect(dashboard, isNot(contains('class _BriefingPersonRow')));
  });
}
