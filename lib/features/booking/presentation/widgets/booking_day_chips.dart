import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'booking_text_styles.dart';

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
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: 7,
        separatorBuilder: (_, _) => const SizedBox(width: 5),
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
                    style: BookingTextStyles.dayLabel(selected: selected),
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 24,
                    height: 24,
                    alignment: const Alignment(0, -0.08),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFBCA36D)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      day.day.toString(),
                      strutStyle: const StrutStyle(
                        fontSize: 15,
                        height: 0.82,
                        forceStrutHeight: true,
                      ),
                      style: BookingTextStyles.dayNumber(selected: selected),
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
