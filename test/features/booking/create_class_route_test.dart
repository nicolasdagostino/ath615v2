import 'package:ath615v2/features/booking/data/class_coach_repository.dart';
import 'package:ath615v2/core/widgets/app_calendar_date_picker_sheet.dart';
import 'package:ath615v2/features/booking/domain/class_coach.dart';
import 'package:ath615v2/features/booking/presentation/booking_colors.dart';
import 'package:ath615v2/features/booking/presentation/widgets/class_coach_selector.dart';
import 'package:ath615v2/features/booking/presentation/widgets/class_form_components.dart';
import 'package:ath615v2/features/booking/presentation/widgets/create_class_sheet.dart';
import 'package:ath615v2/features/booking/presentation/widgets/edit_class_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeCoachRepository implements ClassCoachRepository {
  @override
  Future<List<ClassCoachOption>> listAssignable() async => const [
    ClassCoachOption(
      id: 'coach-1',
      name: 'Alex Coach With A Deliberately Long Display Name',
    ),
  ];
}

final _programs = <Map<String, dynamic>>[
  {
    'id': 'program-1',
    'name': 'Operation LFG With A Deliberately Long Program Name',
  },
];

Widget _routeHarness(Brightness brightness, {required bool edit}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              if (edit) {
                final client = SupabaseClient(
                  'http://localhost',
                  'test-anon-key',
                );
                client.auth.stopAutoRefresh();
                showEditClassSheet(
                  context: context,
                  client: client,
                  gymId: 'gym-1',
                  klass: {
                    'id': 'class-1',
                    'title': 'Preloaded Class Name',
                    'programs': {'name': _programs.first['name']},
                    'starts_at': '2030-08-22T07:30:00',
                    'duration_minutes': 75,
                    'capacity': 18,
                    'program_id': 'program-1',
                    'coach_id': 'coach-1',
                    'coach': {'full_name': 'Alex Coach'},
                  },
                  onUpdated: () async {},
                  coachRepository: _FakeCoachRepository(),
                  programsLoader: () async => _programs,
                );
              } else {
                showCreateClassSheet(
                  context: context,
                  gymId: 'gym-1',
                  onCreated: () async {},
                  coachRepository: _FakeCoachRepository(),
                  programsLoader: () async => _programs,
                );
              }
            },
            child: Text(edit ? 'Open edit class' : 'Open create class'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(
  WidgetTester tester, {
  required Brightness brightness,
  required bool edit,
  Size size = const Size(320, 720),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_routeHarness(brightness, edit: edit));
  await tester.tap(find.text(edit ? 'Open edit class' : 'Open create class'));
  await tester.pumpAndSettle();
}

Future<void> _scrollForm(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -260));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final brightness in Brightness.values) {
    testWidgets('create form fits 320px in ${brightness.name}', (tester) async {
      await _open(tester, brightness: brightness, edit: false);

      expect(find.byType(BookingClassFormScaffold), findsOneWidget);
      expect(find.text('CREATE CLASS'), findsNWidgets(2));
      expect(find.text('DESCRIPTION'), findsOneWidget);
      expect(find.text('Optional · add a brief description'), findsOneWidget);
      expect(find.byType(ClassCoachSelector), findsOneWidget);
      expect(find.text('No Coach'), findsOneWidget);
      final submit = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('booking-class-form-submit')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(submit.onPressed, isNull);

      await _scrollForm(tester);
      expect(find.text('DATE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('DATE')).dy,
        tester.getTopLeft(find.text('TIME')).dy,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.text('DURATION · CAPACITY'), findsOneWidget);
      expect(find.text('Repeat weekly'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('create selectors, recurring state and keyboard remain usable', (
    tester,
  ) async {
    await _open(
      tester,
      brightness: Brightness.light,
      edit: false,
      size: const Size(430, 800),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_programs.first['name'].toString()).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Alex Coach With A Deliberately Long Display Name').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.showKeyboard(find.byType(TextField).first);
    tester.testTextInput.enterText('A long but valid class name');
    await tester.pump();
    expect(tester.takeException(), isNull);
    FocusManager.instance.primaryFocus?.unfocus();

    await _scrollForm(tester);
    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    expect(find.byType(AppCalendarDatePickerSheet), findsOneWidget);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.tap(find.text('${tomorrow.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select time'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'OK'))
        .onPressed!();
    await tester.pumpAndSettle();
    final enabledSubmit = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('booking-class-form-submit')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(enabledSubmit.onPressed, isNotNull);
    await tester.scrollUntilVisible(
      find.byType(Switch),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('REPEAT ON'), findsOneWidget);
    final firstDay = find.byType(ChoiceChip, skipOffstage: false).first;
    await tester.ensureVisible(firstDay);
    await tester.pumpAndSettle();
    await tester.tap(firstDay);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(firstDay).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit uses shared form and keeps preloaded values', (
    tester,
  ) async {
    await _open(tester, brightness: Brightness.dark, edit: true);

    expect(find.byType(BookingClassFormScaffold), findsOneWidget);
    expect(find.text('EDIT CLASS'), findsOneWidget);
    expect(find.text('Preloaded Class Name'), findsOneWidget);
    expect(find.text(_programs.first['name'].toString()), findsOneWidget);
    expect(find.textContaining('Alex Coach'), findsOneWidget);

    await _scrollForm(tester);
    expect(find.text('22/08/2030'), findsOneWidget);
    expect(find.textContaining('7:30'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.text('75'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('booking-class-form-submit')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(submit.onPressed, isNotNull);
    final submitStyle = submit.style;
    expect(
      submitStyle?.backgroundColor?.resolve(<WidgetState>{}),
      BookingColors.primary,
    );
    expect(tester.takeException(), isNull);
  });
}
