import 'dart:convert';
import 'dart:io';

import 'package:ath615v2/core/router/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const returnUrl = 'https://athlete615.com/connect/stripe/return';
  const refreshUrl = 'https://athlete615.com/connect/stripe/refresh';

  test('return Universal Link resolves for cold and resumed delivery', () {
    for (final delivery in ['initial', 'stream']) {
      final action = stripeConnectLinkAction(Uri.parse(returnUrl));
      expect(
        action,
        StripeConnectLinkAction.returnToSettings,
        reason: delivery,
      );
      expect(
        stripeConnectDestination(action!),
        '/gym-settings?stripeConnect=return',
      );
    }
  });

  test('refresh Universal Link and fallback scheme resolve narrowly', () {
    expect(
      stripeConnectLinkAction(Uri.parse(refreshUrl)),
      StripeConnectLinkAction.refreshOnboarding,
    );
    expect(
      stripeConnectLinkAction(Uri.parse('athletelab://connect/stripe/refresh')),
      StripeConnectLinkAction.refreshOnboarding,
    );
    expect(
      stripeConnectLinkAction(Uri.parse('https://athlete615.com/anything')),
      isNull,
    );
    expect(
      stripeConnectLinkAction(
        Uri.parse('https://example.com/connect/stripe/return'),
      ),
      isNull,
    );
  });

  test('unauthenticated destination survives login exactly once', () {
    final pending = PendingDeepLinkDestination();
    pending.remember('/gym-settings?stripeConnect=return');

    expect(pending.take(), '/gym-settings?stripeConnect=return');
    expect(pending.take(), isNull);
  });

  test('AASA contains only the Connect app and paths', () {
    final file = File(
      'hosting/athlete615/.well-known/apple-app-site-association',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final applinks = json['applinks'] as Map<String, dynamic>;
    final details =
        (applinks['details'] as List).single as Map<String, dynamic>;

    expect(details['appID'], 'STG9625267.com.athlete615.ath615v2');
    expect(
      details['paths'],
      unorderedEquals(['/connect/stripe/return', '/connect/stripe/refresh']),
    );
    expect(details['paths'], isNot(contains('*')));
  });

  test('Runner entitlement declares only the production applinks domain', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    expect(entitlements, contains('<string>applinks:athlete615.com</string>'));
    expect(entitlements, isNot(contains('applinks:*')));
  });
}
