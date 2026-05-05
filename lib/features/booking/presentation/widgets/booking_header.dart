import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';

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
            child: Text(
              'ATHLETE LAB',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
          Column(
            children: [
              Text(
                '$month ${selectedDay.year}',
                style: const TextStyle(
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$weekday, ${selectedDay.day}',
                style: const TextStyle(
                  color: Color(0xFF8E94A1),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
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
