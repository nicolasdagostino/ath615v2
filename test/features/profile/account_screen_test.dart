import 'package:ath615v2/core/strings/app_strings.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_form_visuals.dart';
import 'package:ath615v2/features/profile/presentation/screens/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpForm(WidgetTester tester, ThemeMode mode) async {
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
          body: AccountFormContent(
            fullName: TextEditingController(text: 'Nicolás D’Agostino'),
            birthDateLabel: '13/8/1990',
            email: 'nicolas@example.com',
            avatarUrl: null,
            uploadingAvatar: false,
            loading: false,
            onAvatarTap: () {},
            onBirthDateTap: () {},
            onSave: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('account real fields fit 320px in ${mode.name}', (
      tester,
    ) async {
      await pumpForm(tester, mode);

      expect(find.byKey(const ValueKey('account-avatar')), findsOne);
      expect(find.byKey(const ValueKey('account-change-photo')), findsOne);
      expect(find.byKey(const ValueKey('account-full-name')), findsOne);
      expect(find.text('13/8/1990'), findsOne);
      expect(find.byKey(const ValueKey('account-email')), findsOne);
      expect(find.byType(AppFormActionField), findsOne);
      expect(find.byType(AppFormSubmitButton), findsOne);
      expect(find.text(appStrings.profileChangePassword), findsNothing);
      expect(find.text(appStrings.profileSettings), findsNothing);
      final context = tester.element(
        find.byKey(const ValueKey('account-full-name')),
      );
      final nameField = tester.widget<TextField>(
        find.byKey(const ValueKey('account-full-name')),
      );
      expect(nameField.style, appFormValueStyle(context));
      final emailText = tester.widget<Text>(find.text('nicolas@example.com'));
      final sharedValue = appFormValueStyle(context);
      expect(emailText.style?.fontFamily, sharedValue.fontFamily);
      expect(emailText.style?.fontSize, sharedValue.fontSize);
      expect(emailText.style?.fontWeight, sharedValue.fontWeight);
      expect(emailText.style?.height, sharedValue.height);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account-save')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('account-save')), findsOne);
      expect(find.byKey(const ValueKey('account-delete')), findsOne);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account screen uses the shared centered secondary header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AccountScreen(
          profileLoaderForTesting: () async => {
            'full_name': 'Nicolás',
            'birth_date': '1990-08-13',
            'email': 'nicolas@example.com',
            'avatar_url': null,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('account-title')), findsOne);
    expect(find.byKey(const ValueKey('secondary-header-back')), findsOne);
    final title = tester.widget<Text>(
      find.byKey(const ValueKey('account-title')),
    );
    expect(title.style?.fontWeight, FontWeight.w600);
  });
}
