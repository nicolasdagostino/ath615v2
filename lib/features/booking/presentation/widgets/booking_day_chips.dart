import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';

class BookingDayChips extends StatelessWidget {
  const BookingDayChips({
    super.key,
    required this.selectedDay,
    required this.onSelected,
  });

  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelected;

  String _weekdayLabel(DateTime day) {
    return appStrings.weekdayInitials[day.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 14,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = DateTime(
            today.year,
            today.month,
            today.day,
          ).add(Duration(days: index));

          final selected =
              day.year == selectedDay.year &&
              day.month == selectedDay.month &&
              day.day == selectedDay.day;

          return ChoiceChip(
            selected: selected,
            onSelected: (_) => onSelected(day),
            label: SizedBox(
              width: 54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _weekdayLabel(day),
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    day.day.toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
