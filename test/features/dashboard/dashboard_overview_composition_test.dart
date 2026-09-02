import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpDashboard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: buildDashboardCompositionForTest(),
      ),
    );
  }

  void expectCoreDashboardComposition() {
    expect(find.text('ATHLETE 615'), findsNothing);
    expect(find.byKey(const ValueKey('app-primary-a615-logo')), findsOneWidget);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('MEMBERS'), findsAtLeastNWidgets(1));
    expect(find.text('MEMBERSHIPS'), findsOneWidget);
    expect(find.text('ANALYTICS'), findsOneWidget);
    expect(find.byIcon(Icons.notifications), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-kpis')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-attention')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard-today-classes')),
      findsOneWidget,
    );
  }

  testWidgets('composes the production dashboard tree at 390x844', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(390, 844));
    expectCoreDashboardComposition();
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dashboard-analytics')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-activity')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the production dashboard overflow-free at 360x800', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(360, 800));
    expectCoreDashboardComposition();
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Panel header fills and owns the Dynamic Island safe area', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(() => tester.view.padding = FakeViewPadding.zero);
    await pumpDashboard(tester, const Size(390, 844));

    final header = find.byKey(const ValueKey('app-primary-gym-header'));
    expect(tester.getTopLeft(header).dy, 0);
    expect(tester.getSize(header).width, 390);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('app-primary-a615-logo'))).dy,
      greaterThanOrEqualTo(47),
    );
    expect(find.text('ATHLETE 615'), findsNothing);
  });

  test(
    'Panel uses a horizontal selector so membership labels are complete',
    () {
      final source = File(
        'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
      ).readAsStringSync();
      expect(source, contains("ValueKey('dashboard-section-selector')"));
      expect(source, contains('scrollDirection: Axis.horizontal'));
    },
  );
}
