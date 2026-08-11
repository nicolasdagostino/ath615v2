import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_async_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject(Widget child, {ThemeMode themeMode = ThemeMode.light}) {
    return MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders a compact loading state at 360 px', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      subject(const AppAsyncState.loading(message: 'Loading members…')),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading members…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state works in dark mode', (tester) async {
    await tester.pumpWidget(
      subject(
        const AppAsyncState.empty(message: 'No members found.'),
        themeMode: ThemeMode.dark,
      ),
    );

    expect(find.byIcon(Icons.people_outline_rounded), findsOneWidget);
    expect(find.text('No members found.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state exposes an accessible retry action', (tester) async {
    var retries = 0;

    await tester.pumpWidget(
      subject(
        AppAsyncState.error(
          message: 'Members could not be loaded.',
          actionLabel: 'Retry',
          onAction: () => retries++,
        ),
      ),
    );

    final retry = find.widgetWithText(OutlinedButton, 'Retry');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));

    await tester.tap(retry);
    expect(retries, 1);
  });
}
