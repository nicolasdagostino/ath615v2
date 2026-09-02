import 'dart:io';

import 'package:ath615v2/core/router/deep_link_service.dart';
import 'package:ath615v2/features/notifications/navigation/notification_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground, background and cold-start push taps share WOD routing', () {
    final app = File('lib/app/app.dart').readAsStringSync();
    expect(app, contains('isWorkoutNotification(type: type'));
    expect(app, contains('resolveWorkoutDestination('));
    expect(app, contains('onPressed: () => _handlePushTap(message).ignore()'));
    expect(app, contains('FirebaseMessaging.onMessageOpenedApp.listen('));
    expect(app, contains('FirebaseMessaging.instance.getInitialMessage()'));
    expect(app, isNot(contains("_router.push('/workout/")));
  });

  test('foreground workout tap opens the requested WOD destination', () {
    final destination = wodDestination(DateTime(2026, 9, 2));
    expect(
      authenticatedRoute(isAuthenticated: true, destination: destination),
      '/app?section=wod&date=2026-09-02',
    );
  });

  test('background workout tap opens the requested WOD destination', () {
    final destination = wodDestination(DateTime(2026, 9, 2));
    expect(
      authenticatedRoute(isAuthenticated: true, destination: destination),
      '/app?section=wod&date=2026-09-02',
    );
  });

  test('cold-start workout tap survives pending authentication', () {
    const destination = '/app?section=wod&date=2026-09-02';
    final pending = PendingDeepLinkDestination()..remember(destination);

    expect(
      authenticatedRoute(isAuthenticated: false, destination: destination),
      '/login',
    );
    expect(pending.take(), destination);
    expect(pending.take(), isNull);
  });

  test('communication push opens messages inside AppShell', () {
    final app = File('lib/app/app.dart').readAsStringSync();
    expect(app, contains("_router.go('/app?section=messages&notificationId="));
    expect(
      app,
      isNot(contains("_router.push('/notifications?notificationId=")),
    );
  });

  test('legacy workout app links resolve a WOD date instead of detail', () {
    final deepLinks = File(
      'lib/core/router/deep_link_service.dart',
    ).readAsStringSync();
    expect(deepLinks, contains('resolveWorkoutDestination('));
    expect(deepLinks, contains("data: {'workoutId': workoutId}"));
    expect(deepLinks, isNot(contains("_router.push('/workout/")));
  });
}
