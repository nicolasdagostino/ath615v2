import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'booking_text_styles.dart';

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
  late final ScrollController _controller;

  static const double _chipWidth = 56;
  static const double _chipGap = 7;
  static const double _chipExtent = _chipWidth + _chipGap;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: widget.canViewPastDays ? 14 * _chipExtent : 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _weekdayLabel(DateTime day) {
    return appStrings.weekdayInitials[day.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return SizedBox(
      height: 104,
      child: ListView.separated(
        key: ValueKey(widget.canViewPastDays),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: widget.canViewPastDays ? 29 : 14,
        separatorBuilder: (_, _) => const SizedBox(width: _chipGap),
        itemBuilder: (context, index) {
          final offset = widget.canViewPastDays ? index - 14 : index;
          final day = today.add(Duration(days: offset));

          final selected =
              day.year == widget.selectedDay.year &&
              day.month == widget.selectedDay.month &&
              day.day == widget.selectedDay.day;

          return GestureDetector(
            onTap: () => widget.onSelected(day),
            child: SizedBox(
              width: _chipWidth,
              child: Column(
                children: [
                  Text(
                    _weekdayLabel(day),
                    style: BookingTextStyles.dayLabel(selected: selected),
                  ),
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFBCA36D)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      day.day.toString(),
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
