import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/notifications/data/notification_preferences_repository.dart';
import 'package:ath615v2/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakePreferencesRepository implements NotificationPreferencesRepository {
  NotificationPreferences value = const NotificationPreferences.defaults();
  bool failNextWrite = false;

  @override
  Future<NotificationPreferences> loadPreferences() async => value;

  @override
  Future<NotificationPreferences> updateCommunications(bool enabled) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw Exception('write failed');
    }
    return value = NotificationPreferences(
      communicationsPushEnabled: enabled,
      notificationsPushEnabled: value.notificationsPushEnabled,
    );
  }

  @override
  Future<NotificationPreferences> updateNotifications(bool enabled) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw Exception('write failed');
    }
    return value = NotificationPreferences(
      communicationsPushEnabled: value.communicationsPushEnabled,
      notificationsPushEnabled: enabled,
    );
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(
    WidgetTester tester,
    _FakePreferencesRepository repository, {
    ThemeMode mode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: NotificationPreferencesScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to both push categories enabled and persists toggles', (
    tester,
  ) async {
    final repository = _FakePreferencesRepository();
    await pump(tester, repository);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.map((item) => item.value), everyElement(isTrue));

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('communications-push-switch')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.value.communicationsPushEnabled, isFalse);
    expect(repository.value.notificationsPushEnabled, isTrue);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notifications-push-switch')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.value.notificationsPushEnabled, isFalse);
  });

  testWidgets('failed write keeps the persisted switch value', (tester) async {
    final repository = _FakePreferencesRepository()..failNextWrite = true;
    await pump(tester, repository, mode: ThemeMode.dark);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('communications-push-switch')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.value.communicationsPushEnabled, isTrue);
    expect(tester.widgetList<Switch>(find.byType(Switch)).first.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
