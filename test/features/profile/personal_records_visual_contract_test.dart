import 'dart:io';

import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/widgets/app_detail_header.dart';
import 'package:ath615v2/features/profile/presentation/screens/training_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

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
    expect(source, contains('leadingColor: AppColors.primary'));
  });

  testWidgets('Personal Records owns safe area and uses primary back action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.view.padding = FakeViewPadding.zero);

    await tester.pumpWidget(
      const MaterialApp(home: TrainingScreen(recordsOnly: true)),
    );
    await tester.pumpAndSettle();

    final header = find.byType(AppDetailHeader);
    expect(tester.getTopLeft(header).dy, 0);
    final back = tester.widget<Icon>(
      find.byIcon(Icons.arrow_back_ios_new_rounded),
    );
    expect(back.color, AppColors.primary);
    expect(
      tester.getTopLeft(find.byIcon(Icons.arrow_back_ios_new_rounded)).dy,
      greaterThanOrEqualTo(47),
    );
  });
}
