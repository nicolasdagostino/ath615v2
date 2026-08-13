import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in ThemeMode.values.where(
    (mode) => mode != ThemeMode.system,
  )) {
    testWidgets('destructive confirmation fits 320 px in ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const Scaffold(
            body: AppConfirmationDialog(
              title: 'Eliminar WOD',
              message: 'Esta acción no se puede deshacer.',
              confirmLabel: 'Eliminar',
              cancelLabel: 'Cancelar',
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.text('ELIMINAR WOD'), findsOneWidget);
    });
  }
}
