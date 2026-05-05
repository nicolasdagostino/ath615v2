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
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: 14,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
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

          return GestureDetector(
            onTap: () => onSelected(day),
            child: SizedBox(
              width: 46,
              child: Column(
                children: [
                  Text(
                    _weekdayLabel(day),
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFFB69B63)
                          : const Color(0xFF8E94A1),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 46,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFBCA36D)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      day.day.toString(),
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFF090B12),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
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
