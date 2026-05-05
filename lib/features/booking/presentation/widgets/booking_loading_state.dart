import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';

class BookingLoadingState extends StatelessWidget {
  const BookingLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFFB59B6A),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            appStrings.bookingLoadingClasses,
            style: const TextStyle(
              color: Color(0xFF8F96A3),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
