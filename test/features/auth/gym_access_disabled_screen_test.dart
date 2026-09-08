import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/features/auth/presentation/screens/gym_access_disabled_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localeController.setLanguage('en');
  });

  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    required Future<void> Function() signOut,
  }) async {
    final router = GoRouter(
      initialLocation: '/gym-access-disabled',
      routes: [
        GoRoute(
          path: '/gym-access-disabled',
          builder: (_, _) =>
              GymAccessDisabledScreen(signOutForTesting: signOut),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('LOGIN')),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('PROTECTED')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('shows gym-specific disabled copy in English and Spanish', (
    tester,
  ) async {
    await pumpScreen(tester, signOut: () async {});
    expect(find.text('Access disabled'), findsOneWidget);
    expect(
      find.text('Your access to this gym has been disabled.'),
      findsOneWidget,
    );
    expect(find.text('Contact a gym administrator for help.'), findsOneWidget);
    expect(find.text('SIGN OUT'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gym-access-disabled-a615-logo')),
      findsOneWidget,
    );
    expect(find.textContaining('Join gym'), findsNothing);
    expect(find.textContaining('Request access'), findsNothing);

    await localeController.setLanguage('es');
    await tester.pumpWidget(
      MaterialApp(
        home: GymAccessDisabledScreen(signOutForTesting: () async {}),
      ),
    );
    await tester.pump();
    expect(find.text('Acceso desactivado'), findsOneWidget);
    expect(
      find.text('Tu acceso a este gimnasio está desactivado.'),
      findsOneWidget,
    );
    expect(find.text('CERRAR SESIÓN'), findsOneWidget);
  });

  testWidgets('system back cannot reveal protected content', (tester) async {
    final router = await pumpScreen(tester, signOut: () async {});

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/gym-access-disabled',
    );
    expect(find.text('PROTECTED'), findsNothing);
  });

  testWidgets(
    'sign out uses supplied auth flow and replaces route with login',
    (tester) async {
      var signOuts = 0;
      final router = await pumpScreen(tester, signOut: () async => signOuts++);

      await tester.tap(
        find.byKey(const ValueKey('gym-access-disabled-sign-out')),
      );
      await tester.pumpAndSettle();

      expect(signOuts, 1);
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(find.text('LOGIN'), findsOneWidget);
    },
  );
}
