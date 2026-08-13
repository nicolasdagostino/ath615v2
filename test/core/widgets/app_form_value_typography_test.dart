import 'dart:io';

import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'form value and placeholder typography are single shared tokens',
    (tester) async {
      late TextStyle value;
      late TextStyle placeholder;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              value = appFormValueStyle(context);
              placeholder = appFormPlaceholderStyle(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(value.fontFamily, placeholder.fontFamily);
      expect(value.fontSize, placeholder.fontSize);
      expect(value.fontWeight, FontWeight.w500);
      expect(value.height, placeholder.height);
      expect(value.letterSpacing, placeholder.letterSpacing);
    },
  );

  test('Class, Workout and Program forms consume shared value typography', () {
    final sources = [
      File(
        'lib/features/booking/presentation/widgets/create_class_sheet.dart',
      ).readAsStringSync(),
      File(
        'lib/features/booking/presentation/widgets/edit_class_sheet.dart',
      ).readAsStringSync(),
      File(
        'lib/features/workouts/presentation/widgets/workout_form_controls.dart',
      ).readAsStringSync(),
      File(
        'lib/features/workouts/presentation/widgets/manage_programs_sheet.dart',
      ).readAsStringSync(),
    ];

    for (final source in sources) {
      expect(source, contains('appFormValueStyle(context)'));
    }
  });
}
