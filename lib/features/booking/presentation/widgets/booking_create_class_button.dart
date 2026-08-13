import 'package:flutter/material.dart';

import '../booking_colors.dart';

class BookingCreateClassButton extends StatelessWidget {
  const BookingCreateClassButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('booking-create-class'),
    color: BookingColors.primary,
    elevation: 3,
    shadowColor: BookingColors.primary.withValues(alpha: 0.24),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: const SizedBox.square(
        dimension: 52,
        child: Icon(Icons.add_rounded, color: Colors.white, size: 27),
      ),
    ),
  );
}
