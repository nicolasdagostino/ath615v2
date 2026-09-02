import 'dart:async';

import 'package:ath615v2/core/locale/locale_controller.dart';
import 'package:ath615v2/core/theme/app_colors.dart';
import 'package:ath615v2/core/theme/app_system_ui.dart';
import 'package:ath615v2/features/auth/presentation/screens/login_screen.dart';
import 'package:ath615v2/features/public_access/data/demo_request_repository.dart';
import 'package:ath615v2/features/public_access/presentation/screens/public_help_screen.dart';
import 'package:ath615v2/features/public_access/presentation/screens/request_demo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDemoRepository implements DemoRequestRepository {
  final List<DemoRequestInput> submissions = [];
  Completer<void>? completer;
  Object? failure;

  @override
  Future<void> submit(DemoRequestInput request) async {
    submissions.add(request);
    if (failure != null) throw failure!;
    if (completer != null) await completer!.future;
  }
}

GoRouter _router({
  String initialLocation = '/login',
  Future<void> Function(String, String)? signIn,
  DemoRequestRepository? demoRepository,
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, _) =>
          LoginScreen(signInForTesting: signIn ?? (_, _) async {}),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (_, _) => const Scaffold(body: Text('forgot-flow')),
    ),
    GoRoute(path: '/help', builder: (_, _) => const PublicHelpScreen()),
    GoRoute(
      path: '/request-demo',
      builder: (_, _) => RequestDemoScreen(repository: demoRepository),
    ),
  ],
);

Future<void> _pumpRouter(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    AnimatedBuilder(
      animation: localeController,
      builder: (_, _) => MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.byKey(ValueKey(key));

Future<void> _reveal(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    _field(key),
    250,
    scrollable: find.byType(Scrollable).last,
  );
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final button = find.descendant(
    of: _field('demo-submit'),
    matching: find.byType(FilledButton),
  );
  tester.widget<FilledButton>(button).onPressed!();
  await tester.pump();
}

Future<void> _completeRequiredFields(WidgetTester tester) async {
  await tester.enterText(_field('demo-full-name'), '  Ada Lovelace  ');
  await tester.enterText(_field('demo-email'), '  ADA@EXAMPLE.COM ');
  await _reveal(tester, 'demo-gym-name');
  await tester.enterText(_field('demo-gym-name'), '  A615 Box  ');
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localeController.setLanguage('en');
  });

  testWidgets(
    'A615 login uses one logo, localized copy, and no Google action',
    (tester) async {
      await _pumpRouter(tester, _router());

      expect(find.byType(Image), findsNWidgets(2)); // Background plus one logo.
      expect(find.text('A615'), findsNothing);
      expect(find.text('Manage. Train. Grow.'), findsOneWidget);
      expect(find.text('Need help?'), findsOneWidget);
      expect(find.text('Contact us'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Need help?')).style?.color,
        Colors.white,
      );
      expect(
        tester.widget<Text>(find.text('Contact us')).style?.color,
        AppColors.primary,
      );
      final loginOverlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(loginOverlay.value, darkScreenSystemUiOverlayStyle);
      expect(find.textContaining('Google'), findsNothing);

      await localeController.setLanguage('es');
      await _pumpRouter(tester, _router());
      expect(find.text('Gestiona. Entrena. Crece.'), findsOneWidget);
      expect(find.text('¿Necesitas ayuda?'), findsOneWidget);
      expect(find.text('Contáctanos'), findsOneWidget);
    },
  );

  testWidgets('login preserves sign in, password visibility, and forgot flow', (
    tester,
  ) async {
    String? email;
    String? password;
    final router = _router(
      signIn: (value, secret) async {
        email = value;
        password = secret;
      },
    );
    await _pumpRouter(tester, router);
    await tester.tap(find.text('Forgot your password?'));
    await tester.pumpAndSettle();
    expect(find.text('forgot-flow'), findsOneWidget);

    router.go('/login');
    await tester.pumpAndSettle();
    await tester.enterText(_field('login-email'), ' person@example.com ');
    await tester.enterText(_field('login-password'), 'secret');
    expect(
      tester.widget<TextField>(_field('login-password')).obscureText,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('login-password')).obscureText,
      isFalse,
    );
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();
    expect(email, 'person@example.com');
    expect(password, 'secret');
  });

  testWidgets('login is scrollable with keyboard and a simulated notch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await _pumpRouter(tester, _router());
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('login background covers representative iOS and Android sizes', (
    tester,
  ) async {
    const sizes = <String, Size>{
      'iPhone SE': Size(320, 568),
      'iPhone standard': Size(390, 844),
      'iPhone Pro Max': Size(430, 932),
      'Android small': Size(360, 640),
      'Android large': Size(412, 915),
    };

    for (final entry in sizes.entries) {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(
        top: entry.key.startsWith('iPhone') ? 47 : 24,
      );
      await _pumpRouter(tester, _router());
      final background = tester.widget<Image>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/images/a615_login_background.webp',
        ),
      );
      expect(background.fit, BoxFit.cover, reason: entry.key);
      expect(find.text('SIGN IN'), findsOneWidget, reason: entry.key);
      expect(tester.takeException(), isNull, reason: entry.key);
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('public Help is localized and opens Request Demo without auth', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);
    final router = _router(initialLocation: '/help');
    await _pumpRouter(tester, router);
    expect(find.text('HELP'), findsOneWidget);
    expect(find.text('Request a demo'), findsOneWidget);
    expect(find.text('Technical support'), findsOneWidget);
    final helpOverlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(helpOverlay.value, darkScreenSystemUiOverlayStyle);
    final helpBackButton = find.ancestor(
      of: find.byIcon(Icons.arrow_back_ios_new_rounded),
      matching: find.byType(IconButton),
    );
    expect(tester.getTopLeft(helpBackButton).dy, greaterThanOrEqualTo(47));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new_rounded)).color,
      AppColors.primary,
    );
    await tester.tap(find.byKey(const ValueKey('help-request-demo')));
    await tester.pumpAndSettle();
    expect(find.text('REQUEST A DEMO'), findsOneWidget);
    final demoOverlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(demoOverlay.value, darkScreenSystemUiOverlayStyle);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('HELP'), findsOneWidget);

    await localeController.setLanguage('es');
    await _pumpRouter(tester, _router(initialLocation: '/help'));
    expect(find.text('AYUDA'), findsOneWidget);
    expect(find.text('Solicitar una demo'), findsOneWidget);
    expect(find.text('Facturación'), findsOneWidget);
  });

  testWidgets('demo validates required, email, and optional member count', (
    tester,
  ) async {
    final repository = _FakeDemoRepository();
    await _pumpRouter(
      tester,
      _router(initialLocation: '/request-demo', demoRepository: repository),
    );
    await _tapSubmit(tester);
    await tester.pump();
    expect(find.text('This field is required.'), findsNWidgets(3));
    await _reveal(tester, 'demo-email');
    await tester.enterText(_field('demo-email'), 'invalid');
    await _reveal(tester, 'demo-member-count');
    await tester.enterText(_field('demo-member-count'), '-1');
    await _tapSubmit(tester);
    await tester.pump();
    expect(find.text('Enter a valid email.'), findsOneWidget);
    expect(find.text('Enter a whole number of 0 or more.'), findsOneWidget);
    expect(repository.submissions, isEmpty);
  });

  testWidgets('demo normalizes data, prevents double submit, and succeeds', (
    tester,
  ) async {
    final repository = _FakeDemoRepository()..completer = Completer<void>();
    await _pumpRouter(
      tester,
      _router(initialLocation: '/request-demo', demoRepository: repository),
    );
    await _completeRequiredFields(tester);
    await _reveal(tester, 'demo-phone');
    await tester.enterText(_field('demo-phone'), '  +34 600 000 000  ');
    await _reveal(tester, 'demo-member-count');
    await tester.enterText(_field('demo-member-count'), '125');
    await _reveal(tester, 'demo-message');
    await tester.enterText(_field('demo-message'), '  Please call me.  ');
    await _tapSubmit(tester);
    final disabledButton = find.descendant(
      of: _field('demo-submit'),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(disabledButton).onPressed, isNull);
    await tester.pump();
    expect(repository.submissions, hasLength(1));
    final request = repository.submissions.single;
    expect(request.fullName, 'Ada Lovelace');
    expect(request.email, 'ada@example.com');
    expect(request.gymName, 'A615 Box');
    expect(request.approxMemberCount, 125);
    expect(request.locale, 'en');
    repository.completer!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.text('BACK TO SIGN IN'), findsOneWidget);
  });

  testWidgets('demo keeps entered data after human error and supports retry', (
    tester,
  ) async {
    final repository = _FakeDemoRepository()..failure = Exception('internal');
    await _pumpRouter(
      tester,
      _router(initialLocation: '/request-demo', demoRepository: repository),
    );
    await _completeRequiredFields(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't send your request. Please try again."),
      findsOneWidget,
    );
    expect(
      tester.widget<TextFormField>(_field('demo-full-name')).controller!.text,
      contains('Ada'),
    );
    repository.failure = null;
    await _tapSubmit(tester);
    await tester.pumpAndSettle();
    expect(repository.submissions, hasLength(2));
    expect(find.text('Request sent'), findsOneWidget);
  });

  testWidgets('Spanish demo has complete localized copy and handles keyboard', (
    tester,
  ) async {
    await localeController.setLanguage('es');
    tester.view.physicalSize = const Size(375, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await _pumpRouter(
      tester,
      _router(
        initialLocation: '/request-demo',
        demoRepository: _FakeDemoRepository(),
      ),
    );
    expect(find.text('SOLICITAR UNA DEMO'), findsOneWidget);
    expect(find.text('Solicita una demo personalizada'), findsOneWidget);
    await _reveal(tester, 'demo-gym-name');
    expect(find.text('Nombre del gimnasio *'), findsOneWidget);
    await _reveal(tester, 'demo-message');
    expect(
      find.text(
        'Usaremos tus datos únicamente para contactar contigo sobre A615.',
      ),
      findsOneWidget,
    );
    await tester.tap(_field('demo-message'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
