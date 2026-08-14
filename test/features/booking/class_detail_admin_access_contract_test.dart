import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'class detail admin access preserves permission and delete confirmation',
    () {
      final source = File(
        'lib/features/booking/presentation/screens/booking_screen.dart',
      ).readAsStringSync();

      expect(source, contains("_role == 'admin' || _role == 'owner'"));
      expect(source, contains('adminActions: _canManageAttendance'));
      expect(source, contains('attendeeActions: _canManageAttendance'));
      expect(source, contains('onTap: () => _deleteClass(klass)'));
      expect(source, contains('final confirmed = await _confirmDeleteClass'));
      expect(source, contains('if (!confirmed) return;'));
      expect(source, contains('completeClassDeletion('));
      expect(source, contains('Navigator.of(context).pop()'));
      expect(source, contains('refreshSelectedDate: () => _load'));
      expect(source, contains("from('classes').delete()"));
      expect(source, contains("if (klass['recurring_id'] != null)"));
      expect(source, contains('onTap: () => _deleteFutureClasses(klass)'));
      expect(source, contains('showAttendanceAddMember'));
      expect(source, contains('showAttendanceAddGuest'));
      expect(source, isNot(contains('AttendanceInitialAction')));
    },
  );
}
