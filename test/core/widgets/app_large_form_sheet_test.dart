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

  testWidgets(
    'keyboard inset moves and resizes the sheet through one coherent trajectory',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);
      final focusNode = FocusNode();
      final controller = TextEditingController(text: 'Existing description');
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showAppLargeFormSheet<void>(
                    context: context,
                    builder: (_) => Scaffold(
                      resizeToAvoidBottomInset: false,
                      body: Padding(
                        padding: const EdgeInsets.all(24),
                        child: TextField(
                          key: const ValueKey('large-sheet-input'),
                          controller: controller,
                          focusNode: focusNode,
                        ),
                      ),
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
      final input = find.byKey(const ValueKey('large-sheet-input'));
      await tester.tap(input);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      final inputElement = tester.element(input);
      final editableState = tester.state<EditableTextState>(
        find.descendant(of: input, matching: find.byType(EditableText)),
      );

      final positions = <Rect>[tester.getRect(sheet)];
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pump();
      for (var elapsed = 0; elapsed < 180; elapsed += 30) {
        await tester.pump(const Duration(milliseconds: 30));
        positions.add(tester.getRect(sheet));
      }

      for (var index = 1; index < positions.length; index++) {
        expect(
          positions[index].top,
          lessThanOrEqualTo(positions[index - 1].top),
        );
        expect(
          positions[index].bottom,
          lessThanOrEqualTo(positions[index - 1].bottom),
        );
      }
      expect(
        positions.map((rect) => rect.top).reduce((a, b) => a > b ? a : b),
        lessThan(100),
      );
      expect(positions.last.bottom, closeTo(874 - 336, 1));
      expect(focusNode.hasFocus, isTrue);
      expect(tester.element(input), same(inputElement));
      expect(
        tester.state<EditableTextState>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        ),
        same(editableState),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
