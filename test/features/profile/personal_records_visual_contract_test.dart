import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Personal Records contains no legacy accent or gold styling', () {
    final source = File(
      'lib/features/profile/presentation/screens/training_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('AppColors.accent')));
    expect(source.toLowerCase(), isNot(contains('gold')));
    expect(source.toLowerCase(), isNot(contains('amber')));
    expect(source.toLowerCase(), isNot(contains('brown')));
    expect(
      source,
      contains('CircularProgressIndicator(color: AppColors.primary)'),
    );
    expect(
      source,
      contains('BorderSide(color: AppColors.primary, width: 1.2)'),
    );
  });
}
