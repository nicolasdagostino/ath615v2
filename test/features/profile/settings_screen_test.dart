import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/profile/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpSettings(
    WidgetTester tester,
    ThemeMode mode, {
    bool canEditGym = true,
    bool canLeaveGym = false,
  }) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: Scaffold(
          body: SafeArea(
            child: SettingsContent(
              canEditGym: canEditGym,
              canLeaveGym: canLeaveGym,
              leavingGym: false,
              onAccount: () {},
              onChangePassword: () {},
              onGymSettings: () {},
              onNotifications: () {},
              onLanguage: () {},
              onAppearance: () {},
              onHelp: () {},
              onPrivacy: () {},
              onTerms: () {},
              onLeaveGym: () {},
              onLogout: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('settings screen uses a centered secondary header and back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(
                  profileLoaderForTesting: () async => {
                    'role': 'athlete',
                    'gym_id': 'gym-1',
                  },
                ),
              ),
            ),
            child: const Text('OPEN SETTINGS'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN SETTINGS'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-title')), findsOne);
    final title = tester.widget<Text>(
      find.byKey(const ValueKey('settings-title')),
    );
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(find.byKey(const ValueKey('secondary-header-back')), findsOne);
    await tester.tap(find.byKey(const ValueKey('secondary-header-back')));
    await tester.pumpAndSettle();
    expect(find.text('OPEN SETTINGS'), findsOne);
  });

  testWidgets('settings opens the existing change password flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SettingsScreen(
          profileLoaderForTesting: () async => {
            'role': 'athlete',
            'gym_id': 'gym-1',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-change-password')), findsOne);
    expect(find.text(appStrings.profileChangePassword), findsOne);
    await tester.tap(find.byKey(const ValueKey('settings-change-password')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('change-password-new')), findsOne);
    expect(find.byKey(const ValueKey('change-password-confirm')), findsOne);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('settings retains real options at 320px in ${mode.name}', (
      tester,
    ) async {
      await pumpSettings(tester, mode);

      expect(find.text(appStrings.profileAccount), findsOne);
      expect(find.text(appStrings.profileChangePassword), findsOne);
      expect(find.byKey(const ValueKey('settings-notifications')), findsOne);
      expect(find.text(appStrings.notificationPreferences), findsOne);
      expect(find.text(appStrings.profileTraining), findsNothing);
      expect(find.text(appStrings.profileMembership), findsNothing);
      expect(find.text(appStrings.personalRecords), findsNothing);
      expect(find.textContaining(appStrings.profileLanguage), findsOne);
      expect(find.textContaining(appStrings.appearance), findsOne);
      expect(find.text(appStrings.gymInformation), findsOne);
      expect(find.byType(Divider), findsNothing);
      for (final label in [
        appStrings.profileAccount,
        appStrings.profileChangePassword,
      ]) {
        final row = tester.widget<Text>(find.text(label));
        expect(row.style?.fontWeight, FontWeight.w500);
        expect(row.style?.fontWeight?.value ?? 0, lessThanOrEqualTo(600));
        expect(row.style?.fontFamily, contains('Barlow'));
      }
      for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
        if (icon.icon == Icons.chevron_right_rounded) continue;
        expect(icon.color, isNot(const Color(0xFFB59B6A)));
        expect(icon.color, isNot(const Color(0xFF159ED1)));
      }

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-logout')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(appStrings.profileHelp), findsOne);
      expect(find.text(appStrings.profilePrivacyPolicy), findsOne);
      expect(find.text(appStrings.profileTerms), findsOne);
      expect(find.byKey(const ValueKey('settings-logout')), findsOne);
      final logout = tester.widget<Text>(
        find.text(appStrings.profileLogout.toUpperCase()),
      );
      expect(logout.style?.fontWeight, FontWeight.w600);
      await tester.scrollUntilVisible(
        find.textContaining(appStrings.profileDeleteAccount),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining(appStrings.profileDeleteAccount), findsOne);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('athlete keeps leave gym separate from logout', (tester) async {
    await pumpSettings(
      tester,
      ThemeMode.light,
      canEditGym: false,
      canLeaveGym: true,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-leave-gym')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('settings-leave-gym')), findsOne);
    expect(find.byKey(const ValueKey('settings-logout')), findsOne);
    expect(find.text(appStrings.gymInformation), findsNothing);
  });
}
