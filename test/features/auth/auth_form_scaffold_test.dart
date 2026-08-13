import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/auth/presentation/widgets/auth_form_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'auth form remains accessible at 320 px in ${brightness.name} mode',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: AuthFormScaffold(
              title: 'Acceso',
              subtitle: 'Introduce tus credenciales',
              onBack: () {},
              child: Builder(
                builder: (context) => Column(
                  children: [
                    TextField(
                      decoration: authFormInput(
                        context,
                        label: 'Email',
                        icon: Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const FilledButton(
                      onPressed: null,
                      child: Text('CONTINUAR'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('ACCESO'), findsOneWidget);
        expect(find.text('Email'), findsWidgets);
      },
    );
  }
}
