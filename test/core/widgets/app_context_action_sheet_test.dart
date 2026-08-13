import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_context_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required ThemeData theme,
    VoidCallback? onEdit,
  }) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AppContextActionSheet(
            title: 'Operation LFG',
            eyebrow: 'Workout options',
            actions: [
              AppContextActionRow(
                icon: Icons.edit_outlined,
                label: 'Edit',
                subtitle: 'Operation LFG',
                onTap: onEdit ?? () {},
              ),
              AppContextActionRow(
                icon: Icons.delete_outline,
                label: 'Delete',
                subtitle: 'Operation LFG',
                destructive: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('context actions fit a 320px viewport and dispatch taps', (
    tester,
  ) async {
    var edited = false;
    await pumpSheet(tester, theme: AppTheme.light, onEdit: () => edited = true);

    await tester.tap(find.text('Edit'));
    expect(edited, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'destructive actions use the semantic danger color in dark mode',
    (tester) async {
      await pumpSheet(tester, theme: AppTheme.dark);

      final deleteText = tester.widget<Text>(find.text('Delete'));
      expect(deleteText.style?.color, AppColors.danger);
      expect(tester.takeException(), isNull);
    },
  );
}
