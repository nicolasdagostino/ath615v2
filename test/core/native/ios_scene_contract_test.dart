import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

String pluginSource(String package, String path) {
  final config = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final entry = packages.cast<Map>().singleWhere((p) => p['name'] == package);
  final rootUri = entry['rootUri'] as String;
  final root = Directory.fromUri(Uri.parse(rootUri));
  return File(
    [root.path, path].join(Platform.pathSeparator),
  ).readAsStringSync();
}

void main() {
  final plist = read('ios/Runner/Info.plist');
  final delegate = read('ios/Runner/AppDelegate.swift');

  test('Runner declares one Flutter storyboard scene', () {
    expect(plist, contains('<key>UIApplicationSceneManifest</key>'));
    expect(
      plist,
      matches(r'<key>UIApplicationSupportsMultipleScenes</key>\s*<false/>'),
    );
    expect(plist, contains('<key>UISceneConfigurations</key>'));
    expect(plist, contains('<key>UIWindowSceneSessionRoleApplication</key>'));
    expect(
      plist,
      matches(
        r'<key>UISceneDelegateClassName</key>\s*<string>FlutterSceneDelegate</string>',
      ),
    );
    expect(
      plist,
      matches(r'<key>UISceneStoryboardFile</key>\s*<string>Main</string>'),
    );
    expect(
      read('ios/Runner/Base.lproj/Main.storyboard'),
      contains('customClass="FlutterViewController"'),
    );
  });

  test('implicit Flutter engine registers plugins once after initialization', () {
    expect(
      delegate,
      contains('FlutterAppDelegate, FlutterImplicitEngineDelegate'),
    );
    expect(
      RegExp(r'GeneratedPluginRegistrant\.register').allMatches(delegate),
      hasLength(1),
    );
    expect(
      delegate,
      matches(
        r'func didInitializeImplicitFlutterEngine\(_ engineBridge: FlutterImplicitEngineBridge\)\s*\{\s*GeneratedPluginRegistrant.register\(with: engineBridge.pluginRegistry\)',
      ),
    );
    expect(
      delegate,
      contains(
        'super.application(application, didFinishLaunchingWithOptions: launchOptions)',
      ),
    );
    expect(delegate, isNot(matches(RegExp(r'(?<!Implicit)FlutterEngine\('))));
    expect(delegate, isNot(contains('rootViewController =')));
  });

  test(
    'installed app_links handles cold and warm scene URLs and universal links',
    () {
      final source = pluginSource(
        'app_links',
        'ios/app_links/Sources/app_links/AppLinksIosPlugin.swift',
      );
      for (final contract in [
        'FlutterSceneLifeCycleDelegate',
        'registrar.addSceneDelegate(instance)',
        'willConnectTo session:',
        'options.urlContexts',
        'options.userActivities',
        'openURLContexts URLContexts:',
        'continue userActivity:',
        'handleLink(url: context.url)',
        'userActivity.webpageURL',
      ]) {
        expect(source, contains(contract));
      }
      expect(
        plist,
        matches(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>'),
      );
      expect(plist, contains('<string>athletelab</string>'));
    },
  );

  test('PKCE recovery remains handled by existing recovery routing', () {
    final source = read('lib/core/router/deep_link_service.dart');
    expect(source, contains('getInitialLink()'));
    expect(source, contains('uriLinkStream.listen'));
    expect(source, contains("'/reset-password'"));
    final recovery = read(
      'lib/features/auth/data/password_recovery_controller.dart',
    );
    expect(recovery, contains("uri.scheme.toLowerCase() == 'athletelab'"));
    expect(recovery, contains("uri.host.toLowerCase() == 'reset-password'"));
  });

  test('associated domain and both Stripe callbacks remain configured', () {
    expect(
      read('ios/Runner/Runner.entitlements'),
      contains('applinks:athlete615.com'),
    );
    final source = read('lib/core/router/deep_link_service.dart');
    expect(source, contains("'/connect/stripe/return'"));
    expect(source, contains("'/connect/stripe/refresh'"));
  });

  test(
    'installed Firebase plugin forwards scene notification launch and taps',
    () {
      final source = pluginSource(
        'firebase_messaging',
        'ios/firebase_messaging/Sources/firebase_messaging/FLTFirebaseMessagingPlugin.m',
      );
      for (final contract in [
        '@selector(addSceneDelegate:)',
        'willConnectToSession:',
        'connectionOptions.notificationResponse',
        'setupNotificationHandlingWithRemoteNotification:',
        'didReceiveNotificationResponse:',
      ]) {
        expect(source, contains(contract));
      }
      expect(
        read('ios/Runner/Runner.entitlements'),
        contains('<key>aps-environment</key>'),
      );
    },
  );

  test('iOS 15 minimum and centralized Pod target floor are preserved', () {
    final project = read('ios/Runner.xcodeproj/project.pbxproj');
    final targets = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);',
    ).allMatches(project);
    expect(targets, isNotEmpty);
    expect(targets.map((m) => m[1]), everyElement('15.0'));
    final pods = read('ios/Podfile');
    expect(pods, contains("platform :ios, '15.0'"));
    expect(
      pods,
      contains(
        "Gem::Version.new(deployment_target) < Gem::Version.new('15.0')",
      ),
    );
  });
}
