import 'package:ath615v2/core/theme/app_theme.dart';
import 'package:ath615v2/core/widgets/app_week_date_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drag follows the pointer and snaps to the next week', (
    tester,
  ) async {
    final start = DateTime(2026, 8, 10);
    DateTime? visibleWeek;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppWeekDateSelector(
            days: List.generate(
              21,
              (index) => start.add(Duration(days: index)),
            ),
            selectedDay: start,
            today: start,
            weekdayLabel: (_) => 'MON',
            onSelected: (_) {},
            onVisibleWeekChanged: (value) => visibleWeek = value,
            accentColor: const Color(0xFF159ED1),
          ),
        ),
      ),
    );

    final page = find.byKey(const ValueKey('app-week-date-pages'));
    final gesture = await tester.startGesture(tester.getCenter(page));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-500, 0));
    await tester.pump();
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: page, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.pixels, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(visibleWeek, DateTime(2026, 8, 17));
  });

  testWidgets('selected wins over today and unselected today is outlined', (
    tester,
  ) async {
    final today = DateTime(2026, 8, 17);
    final selected = DateTime(2026, 8, 18);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppWeekDateSelector(
            days: List.generate(7, (index) => today.add(Duration(days: index))),
            selectedDay: selected,
            today: today,
            weekdayLabel: (_) => 'DAY',
            onSelected: (_) {},
            accentColor: const Color(0xFF159ED1),
          ),
        ),
      ),
    );

    final selectedDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const ValueKey('app-selected-day')),
                )
                .decoration
            as BoxDecoration;
    expect(selectedDecoration.color, const Color(0xFF159ED1));
    expect(selectedDecoration.border, isNull);

    final todayText = find.text('17');
    final todayContainer = find.ancestor(
      of: todayText,
      matching: find.byType(AnimatedContainer),
    );
    final todayDecoration =
        tester.widget<AnimatedContainer>(todayContainer).decoration
            as BoxDecoration;
    expect(todayDecoration.color, Colors.transparent);
    expect(todayDecoration.border, isNotNull);
  });
}
