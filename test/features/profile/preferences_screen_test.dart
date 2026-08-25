import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/core/preferences/app_preferences_controller.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/theme/theme_controller.dart';
import 'package:ath615v2/features/profile/presentation/screens/preferences_screen.dart';
import 'package:ath615v2/features/profile/presentation/screens/settings_resource_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> resetPreferences() async {
    SharedPreferences.setMockInitialValues({});
    await localeController.load();
    await themeController.load();
    await appPreferencesController.load();
  }

  Future<void> pumpPreferences(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const PreferencesScreen(),
      ),
    );
  }

  testWidgets('preferences persist theme, language, time and units', (
    tester,
  ) async {
    await resetPreferences();
    await pumpPreferences(tester);

    await tester.tap(find.byKey(const ValueKey('preference-theme-dark')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('preference-language-en')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('preference-time-12')),
      180,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byKey(const ValueKey('preference-time-12')));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('preference-units-imperial')),
      180,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byKey(const ValueKey('preference-units-imperial')));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode'), 'dark');
    expect(prefs.getString('app_language'), 'en');
    expect(prefs.getString('app_time_format'), 'twelveHour');
    expect(prefs.getString('app_unit_system'), 'imperial');
    expect(themeController.themeMode, ThemeMode.dark);
    expect(localeController.locale.languageCode, 'en');
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar preference remains visibly disabled', (tester) async {
    await resetPreferences();
    await pumpPreferences(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('preference-calendar-disabled')),
      250,
      scrollable: find.byType(Scrollable),
    );
    final inkWell = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('preference-calendar-disabled')),
        matching: find.byType(InkWell),
      ),
    );
    expect(inkWell.onTap, isNull);
  });

  for (final type in SettingsResourceType.values) {
    testWidgets('${type.name} only presents real or explicit empty data', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SettingsResourceScreen(
            type: type,
            paymentsHistoryLoader: () async => const [],
          ),
        ),
      );
      if (type == SettingsResourceType.legal) {
        expect(find.byKey(const ValueKey('legal-privacy')), findsOne);
        expect(find.byKey(const ValueKey('legal-terms')), findsOne);
      } else if (type == SettingsResourceType.documents) {
        expect(find.byKey(const ValueKey('documents-empty')), findsOne);
      } else {
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('payments-methods-empty')), findsOne);
        expect(find.byKey(const ValueKey('payments-history-empty')), findsOne);
        expect(find.byIcon(Icons.credit_card), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
