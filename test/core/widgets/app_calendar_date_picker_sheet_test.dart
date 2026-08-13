import 'dart:io';

import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_calendar_date_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('es');
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('shared calendar selects and cancels at 320px ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAppCalendarDatePickerSheet(
                  context: context,
                  initialDate: DateTime(2026, 8, 13),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2026, 8, 13),
                  accentColor: AppColors.primary,
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.byType(AppCalendarDatePickerSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey('app-calendar-date-picker-close')),
      );
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  }

  testWidgets('shared calendar follows Spanish locale', (tester) async {
    await localeController.setLanguage('es');
    addTearDown(() async => localeController.setLanguage('en'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AppCalendarDatePickerSheet(
          initialDate: DateTime(2026, 8, 13),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          accentColor: AppColors.primary,
        ),
      ),
    );
    expect(find.text('SELECCIONAR FECHA'), findsOneWidget);
  });

  test('all date consumers use the shared picker entry point', () {
    for (final path in [
      'lib/features/booking/presentation/widgets/create_class_sheet.dart',
      'lib/features/booking/presentation/widgets/edit_class_sheet.dart',
      'lib/features/workouts/presentation/widgets/create_workout_sheet.dart',
      'lib/features/workouts/presentation/widgets/edit_workout_sheet.dart',
      'lib/features/profile/presentation/screens/account_screen.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('showAppDatePicker('));
    }
    expect(
      File('lib/core/widgets/app_pickers.dart').readAsStringSync(),
      contains('showAppCalendarDatePickerSheet('),
    );
    expect(
      File(
        'lib/features/workouts/presentation/screens/workouts_screen.dart',
      ).readAsStringSync(),
      contains('showAppCalendarDatePickerSheet('),
    );
  });
}
