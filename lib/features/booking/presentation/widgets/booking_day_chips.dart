import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_week_date_selector.dart';
import '../booking_colors.dart';

class BookingDayChips extends StatefulWidget {
  const BookingDayChips({
    super.key,
    required this.selectedDay,
    required this.onSelected,
    this.canViewPastDays = false,
  });

  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelected;
  final bool canViewPastDays;

  @override
  State<BookingDayChips> createState() => _BookingDayChipsState();
}

class _BookingDayChipsState extends State<BookingDayChips> {
  static const int _pastDays = 14;
  static const int _futureDays = 14;
  String _weekdayLabel(DateTime day) {
    const english = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const spanish = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
    return (appStrings.isEs ? spanish : english)[day.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startOffset = widget.canViewPastDays ? -_pastDays : 0;
    final itemCount = widget.canViewPastDays ? _pastDays + _futureDays + 1 : 7;

    final days = List.generate(
      itemCount,
      (index) => DateTime(
        today.year,
        today.month,
        today.day,
      ).add(Duration(days: startOffset + index)),
    );
    return AppWeekDateSelector(
      days: days,
      selectedDay: widget.selectedDay,
      weekdayLabel: _weekdayLabel,
      onSelected: widget.onSelected,
      accentColor: BookingColors.primary,
      today: today,
      itemSpacing: widget.canViewPastDays ? AppSpacing.xs : 0,
      selectedKey: const ValueKey('booking-selected-day'),
    );
  }
}
