import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/core/preferences/app_preferences_controller.dart';
import 'package:ath615v2/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fresh installation defaults to Spanish, light, 24h and metric',
    () async {
      SharedPreferences.setMockInitialValues({});
      final locale = LocaleController();
      final theme = ThemeController();
      final preferences = AppPreferencesController();

      await locale.load();
      await theme.load();
      await preferences.load();

      expect(locale.locale.languageCode, 'es');
      expect(theme.themeMode, ThemeMode.light);
      expect(preferences.timeFormat, AppTimeFormat.twentyFourHour);
      expect(preferences.unitSystem, AppUnitSystem.metric);
    },
  );

  test(
    'saved English, dark and user preferences are never overwritten',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_language': 'en',
        'app_theme_mode': 'dark',
        'app_time_format': 'twelveHour',
        'app_unit_system': 'imperial',
      });
      final locale = LocaleController();
      final theme = ThemeController();
      final preferences = AppPreferencesController();

      await locale.load();
      await theme.load();
      await preferences.load();

      expect(locale.locale.languageCode, 'en');
      expect(theme.themeMode, ThemeMode.dark);
      expect(preferences.timeFormat, AppTimeFormat.twelveHour);
      expect(preferences.unitSystem, AppUnitSystem.imperial);
    },
  );

  test('saved system theme remains system after restart', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'system'});
    final theme = ThemeController();
    await theme.load();
    expect(theme.themeMode, ThemeMode.system);
  });

  test('time formatter provides shared Booking 24h and 12h output', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = AppPreferencesController();
    await preferences.load();
    final time = DateTime(2026, 8, 25, 18, 5);
    expect(preferences.formatTime(time), '18:05');
    await preferences.setTimeFormat(AppTimeFormat.twelveHour);
    expect(preferences.formatTime(time), '6:05 PM');
  });
}
