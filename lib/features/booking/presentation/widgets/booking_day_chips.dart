import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
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

  static const int _pastDays = 14;
  static const int _futureDays = 14;
  static const double _itemExtent = 46 + 5;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients || !widget.canViewPastDays) return;
      _controller.jumpTo(_pastDays * _itemExtent);
    });
  }

  @override
  void didUpdateWidget(covariant BookingDayChips oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.canViewPastDays && widget.canViewPastDays) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        _controller.jumpTo(_pastDays * _itemExtent);
      });
    }
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
    final today = DateTime.now();
    final startOffset = widget.canViewPastDays ? -_pastDays : 0;
    final itemCount = widget.canViewPastDays ? _pastDays + _futureDays + 1 : 7;

    return SizedBox(
      height: 58,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final day = DateTime(
            today.year,
            today.month,
            today.day,
          ).add(Duration(days: startOffset + index));

          final selected =
              day.year == widget.selectedDay.year &&
              day.month == widget.selectedDay.month &&
              day.day == widget.selectedDay.day;

          return GestureDetector(
            onTap: () => widget.onSelected(day),
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
                      style: BookingTextStyles.dayNumber(selected: selected)
                          .copyWith(
                            color: selected
                                ? Colors.white
                                : AppColors.textPrimary(context),
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
