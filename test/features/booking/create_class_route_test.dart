import 'package:ath615v2/features/booking/data/class_coach_repository.dart';
import 'package:ath615v2/features/booking/domain/class_coach.dart';
import 'package:ath615v2/features/booking/presentation/widgets/create_class_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeCoachRepository implements ClassCoachRepository {
  @override
  Future<List<ClassCoachOption>> listAssignable() async {
    return const [ClassCoachOption(id: 'coach-1', name: 'Alex Coach')];
  }
}

Widget _routeHarness(Brightness brightness) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showCreateClassSheet(
              context: context,
              gymId: 'gym-1',
              onCreated: () async {},
              coachRepository: _FakeCoachRepository(),
              programsLoader: () async => [
                {'id': 'program-1', 'name': 'Operation LFG'},
              ],
            ),
            child: const Text('Open create class'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _expectProductionComposition(
  WidgetTester tester,
  Brightness brightness,
) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_routeHarness(brightness));

  await tester.tap(find.text('Open create class'));
  await tester.pumpAndSettle();

  expect(find.text('CREATE CLASS'), findsNWidgets(2));
  expect(find.text('Program'), findsWidgets);
  expect(find.text('Coach'), findsOneWidget);
  expect(find.text('No Coach'), findsOneWidget);
  expect(find.text('Date'), findsOneWidget);
  expect(find.text('Time'), findsOneWidget);
  expect(find.text('Duration'), findsOneWidget);
  expect(find.text('Capacity'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('real create-class route renders all fields at 360px in light', (
    tester,
  ) async {
    await _expectProductionComposition(tester, Brightness.light);
  });

  testWidgets('real create-class route renders all fields at 360px in dark', (
    tester,
  ) async {
    await _expectProductionComposition(tester, Brightness.dark);
  });
}
