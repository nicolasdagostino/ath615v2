import 'package:ath615v2/features/booking/domain/class_coach.dart';
import 'package:ath615v2/features/booking/presentation/widgets/class_coach_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _eligibleCoaches = [
  ClassCoachOption(id: 'athlete-coach', name: 'Athlete Coach'),
  ClassCoachOption(id: 'admin-coach', name: 'Admin Coach'),
  ClassCoachOption(id: 'legacy-coach', name: 'Legacy Coach'),
];

Widget _subject({
  List<ClassCoachOption> coaches = _eligibleCoaches,
  String? selectedCoachId,
  String? currentCoachId,
  String? currentCoachName,
  bool loading = false,
  Object? error,
  ValueChanged<String?>? onChanged,
  VoidCallback? onRetry,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ClassCoachSelector(
          coaches: coaches,
          selectedCoachId: selectedCoachId,
          currentCoachId: currentCoachId,
          currentCoachName: currentCoachName,
          loading: loading,
          error: error,
          onChanged: onChanged ?? (_) {},
          onRetry: onRetry ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'shows athlete, admin and legacy Coaches returned by the effective RPC',
    (tester) async {
      await tester.pumpWidget(_subject());
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Athlete Coach'), findsWidgets);
      expect(find.text('Admin Coach'), findsWidgets);
      expect(find.text('Legacy Coach'), findsWidgets);
      expect(find.text('Athlete without Coach'), findsNothing);
      expect(find.text('Admin without Coach'), findsNothing);
      expect(find.text('Inactive Coach'), findsNothing);
    },
  );

  testWidgets('keeps a currently selected assignable Coach when editing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        selectedCoachId: 'admin-coach',
        currentCoachId: 'admin-coach',
        currentCoachName: 'Admin Coach',
      ),
    );

    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(selector.initialValue, 'admin-coach');
    expect(find.byKey(const Key('class-coach-unavailable')), findsNothing);
  });

  testWidgets('shows an unavailable historical Coach without removing it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        selectedCoachId: 'historic-coach',
        currentCoachId: 'historic-coach',
        currentCoachName: 'Historic Coach',
      ),
    );

    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(selector.initialValue, 'historic-coach');
    expect(find.byKey(const Key('class-coach-unavailable')), findsOneWidget);
    expect(find.textContaining('cannot be selected'), findsOneWidget);
  });

  testWidgets('supports creating a class without Coach', (tester) async {
    await tester.pumpWidget(_subject());
    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(selector.initialValue, '');
    expect(find.text('No Coach'), findsOneWidget);
  });

  testWidgets('returns the selected Coach id', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _subject(onChanged: (coachId) => selected = coachId),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin Coach').last);
    await tester.pumpAndSettle();

    expect(selected, 'admin-coach');
  });

  testWidgets('returns null when Coach is cleared', (tester) async {
    String? selected = 'admin-coach';
    await tester.pumpWidget(
      _subject(
        selectedCoachId: 'admin-coach',
        onChanged: (coachId) => selected = coachId,
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No Coach').last);
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });

  testWidgets('shows the empty state when the RPC returns no Coaches', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(coaches: const []));
    expect(find.byKey(const Key('class-coach-empty')), findsOneWidget);
  });

  testWidgets('shows an error and retries', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _subject(error: StateError('network'), onRetry: () => retries += 1),
    );

    expect(find.byKey(const Key('class-coach-error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('shows a finite loading state', (tester) async {
    await tester.pumpWidget(_subject(loading: true));
    expect(find.byKey(const Key('class-coach-loading')), findsOneWidget);
  });

  testWidgets('fits at 360 logical pixels without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_subject());
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark mode without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_subject(brightness: Brightness.dark));
    expect(tester.takeException(), isNull);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });
}
