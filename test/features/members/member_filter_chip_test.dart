import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/features/members/presentation/widgets/member_filter_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('active member filter is selected and remains tappable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MemberFilterChip(
            label: 'All 26',
            selected: true,
            onTap: () => taps++,
          ),
        ),
      ),
    );

    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    expect(chip.selected, isTrue);
    expect(find.text('ALL 26'), findsOneWidget);

    await tester.tap(find.byType(ChoiceChip));
    expect(taps, 1);
  });
}
