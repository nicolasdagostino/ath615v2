import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Coach repository delegates eligibility to the effective backend RPC',
    () {
      final source = File(
        'lib/features/booking/data/class_coach_repository.dart',
      ).readAsStringSync();

      expect(source, contains("rpc('list_assignable_class_coaches')"));
      expect(source, isNot(contains("from('profiles')")));
      expect(source, isNot(contains("role == 'coach'")));
      expect(source, isNot(contains("'gym_id'")));
    },
  );

  test(
    'create uses effective Coach loading and sends coach ids in all paths',
    () {
      final source = File(
        'lib/features/booking/presentation/widgets/create_class_sheet.dart',
      ).readAsStringSync();

      expect(source, contains('SupabaseClassCoachRepository'));
      expect(source, contains("'create_recurring_classes_multi'"));
      expect(source, contains("'create_recurring_classes'"));
      expect(source, contains('withRecurringClassCoach'));
      expect(source, contains('withClassCoach'));
      expect(source, contains('_selectedCoachId'));
    },
  );

  test('edit preserves the description field and coach id in its payload', () {
    final source = File(
      'lib/features/booking/presentation/widgets/edit_class_sheet.dart',
    ).readAsStringSync();

    expect(source, contains("widget.klass['coach_id']"));
    expect(source, contains("widget.klass['title']"));
    expect(source, contains('controller: _description'));
    expect(source, contains("'title': classTitle"));
    expect(source, contains('_selectedCoachId = _currentCoachId'));
    expect(source, contains('currentCoachName: _currentCoachName'));
    expect(source, contains('withClassCoach'));
  });

  test('class loader fetches current Coach identity in one query', () {
    final source = File(
      'lib/features/booking/presentation/screens/booking_screen.dart',
    ).readAsStringSync();

    expect(source, contains('coach_id'));
    expect(
      source,
      contains('coach:profiles!classes_coach_id_fkey(full_name, avatar_url)'),
    );
  });
}
