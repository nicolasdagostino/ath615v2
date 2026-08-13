import 'dart:io';

import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:ath615v2/features/workouts/presentation/widgets/manage_programs_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final client = SupabaseClient('https://example.supabase.co', 'test-key');

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'Program form is shared, image-free and fits 320px ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            home: ProgramFormView(client: client, gymId: 'gym-1'),
          ),
        );

        expect(find.byType(AppFormHeader), findsOneWidget);
        expect(find.byType(AppFormSectionLabel), findsOneWidget);
        expect(find.byType(AppFormSubmitButton), findsOneWidget);
        expect(
          find.byKey(const ValueKey('program-name-field')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.image_outlined), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('Programs UI has pencil/actions and exposes no image capability', () {
    final source = File(
      'lib/features/workouts/presentation/widgets/manage_programs_sheet.dart',
    ).readAsStringSync();
    expect(source, contains('AppOutlinedAdminButton('));
    expect(source, contains('AppAdminActionSheet('));
    expect(source, contains('appStrings.editProgram'));
    expect(source, contains('appStrings.deleteProgram'));
    expect(source, isNot(contains('image_picker')));
    expect(source, isNot(contains('image_url')));
    expect(source, isNot(contains('Icons.more_horiz')));
    expect(source, isNot(contains('changeImage')));
  });
}
