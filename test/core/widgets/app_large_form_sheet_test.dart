import 'package:ath615v2/core/theme/app_design_tokens.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_large_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'large form sheet leaves the top visible at 320px ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showAppLargeFormSheet<void>(
                      context: context,
                      builder: (_) => const Scaffold(
                        body: TextField(key: ValueKey('large-sheet-input')),
                      ),
                    ),
                    child: const Text('OPEN'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OPEN'));
        await tester.pumpAndSettle();

        final sheet = find.byKey(const ValueKey('app-large-form-sheet'));
        expect(sheet, findsOneWidget);
        expect(
          tester.getSize(sheet).height,
          closeTo(800 * appLargeFormSheetHeightFactor, 1),
        );
        expect(tester.getTopLeft(sheet).dy, greaterThan(0));
        final clip = tester.widget<ClipRRect>(
          find.ancestor(of: sheet, matching: find.byType(ClipRRect)).first,
        );
        expect(
          clip.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
