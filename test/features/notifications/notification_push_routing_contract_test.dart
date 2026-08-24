import 'dart:io';

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

  test('legacy workout app links resolve a WOD date instead of detail', () {
    final deepLinks = File(
      'lib/core/router/deep_link_service.dart',
    ).readAsStringSync();
    expect(deepLinks, contains('resolveWorkoutDestination('));
    expect(deepLinks, contains("data: {'workoutId': workoutId}"));
    expect(deepLinks, isNot(contains("_router.push('/workout/")));
  });
}
