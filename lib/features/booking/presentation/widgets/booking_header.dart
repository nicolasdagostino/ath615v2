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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Text('ATHLETE LAB', style: BookingTextStyles.headerBrand),
          ),
          Text(
            appStrings.bookingTitle.toUpperCase(),
            style: BookingTextStyles.headerMonth,
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
