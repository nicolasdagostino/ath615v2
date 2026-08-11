import 'package:ath615v2/features/members/presentation/widgets/member_role_capability_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _subject({required String role, required bool isCoach}) {
  return MaterialApp(
    home: Scaffold(
      body: MemberRoleCapabilitySection(
        role: role,
        isCoach: isCoach,
        isUpdatingCoach: false,
        onRoleSelected: (_) {},
        onCoachChanged: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('renders athlete and Coach as independent member attributes', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(role: 'athlete', isCoach: true));

    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('member-coach-capability-switch')),
    );
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNotNull);

    final athlete = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Athlete'),
    );
    expect(athlete.selected, isTrue);
  });

  testWidgets('renders admin plus Coach without changing the selected role', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(role: 'admin', isCoach: true));

    final admin = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Admin'),
    );
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('member-coach-capability-switch')),
    );

    expect(admin.selected, isTrue);
    expect(tile.value, isTrue);
  });

  testWidgets('keeps legacy Coach capability enabled and explains why', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(role: 'coach', isCoach: true));

    final legacyCoach = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'COACH'),
    );
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('member-coach-capability-switch')),
    );

    expect(legacyCoach.selected, isTrue);
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNull);
    expect(
      find.textContaining('Legacy Coach role includes this capability'),
      findsOneWidget,
    );
  });

  testWidgets('fits the member detail control at 360 logical pixels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_subject(role: 'admin', isCoach: true));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('member-coach-capability-switch')),
      findsOneWidget,
    );
  });
}
