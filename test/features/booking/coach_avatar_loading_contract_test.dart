import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'coach avatars are joined in class batches without per-card queries',
    () {
      final booking = File(
        'lib/features/booking/presentation/screens/booking_screen.dart',
      ).readAsStringSync();
      final reservations = File(
        'lib/features/booking/data/my_reservations_data_source.dart',
      ).readAsStringSync();
      final detail = File(
        'lib/features/booking/presentation/widgets/class_details_sheet.dart',
      ).readAsStringSync();

      expect(booking, contains('full_name, avatar_url'));
      expect(reservations, contains('full_name,avatar_url'));
      expect(detail, contains("profilesById[coachId]"));
      expect(detail, isNot(contains(".eq('id', coachId)")));
    },
  );
}
