import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'booking_text_styles.dart';

class BookingHeader extends StatelessWidget {
  const BookingHeader({
    super.key,
    required this.selectedDay,
    required this.onRefresh,
  });

  final DateTime selectedDay;
  final VoidCallback onRefresh;

  static const _monthsEn = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  static const _monthsEs = [
    'ENERO',
    'FEBRERO',
    'MARZO',
    'ABRIL',
    'MAYO',
    'JUNIO',
    'JULIO',
    'AGOSTO',
    'SEPTIEMBRE',
    'OCTUBRE',
    'NOVIEMBRE',
    'DICIEMBRE',
  ];

  static const _weekdaysEn = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const _weekdaysEs = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  @override
  Widget build(BuildContext context) {
    final isEs = appStrings.isEs;
    final month = isEs
        ? _monthsEs[selectedDay.month - 1]
        : _monthsEn[selectedDay.month - 1];
    final weekday = isEs
        ? _weekdaysEs[selectedDay.weekday - 1]
        : _weekdaysEn[selectedDay.weekday - 1];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Text('ATHLETE LAB', style: BookingTextStyles.headerBrand),
          ),
          Column(
            children: [
              Text(
                '$month ${selectedDay.year}',
                style: BookingTextStyles.headerMonth,
              ),
              const SizedBox(height: 8),
              Text(
                '$weekday, ${selectedDay.day}',
                style: BookingTextStyles.headerSubtitle,
              ),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton.filledTonal(
                onPressed: onRefresh,
                icon: const Icon(Icons.calendar_month_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF4EFE6),
                  foregroundColor: const Color(0xFFB69B63),
                  fixedSize: const Size(38, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
