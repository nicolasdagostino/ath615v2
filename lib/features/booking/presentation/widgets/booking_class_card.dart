import 'package:flutter/material.dart';

import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_outlined_button.dart';

class BookingClassCard extends StatelessWidget {
  const BookingClassCard({
    super.key,
    required this.klass,
    required this.bookedCount,
    required this.capacity,
    required this.buttonLabel,
    required this.buttonAction,
    required this.canManageAttendance,
    required this.onOpenAttendance,
    this.onMorePressed,
    required this.formatDateTime,
  });

  final Map<String, dynamic> klass;
  final int bookedCount;
  final int capacity;
  final String buttonLabel;
  final VoidCallback? buttonAction;
  final bool canManageAttendance;
  final VoidCallback? onOpenAttendance;
  final VoidCallback? onMorePressed;
  final String Function(String raw) formatDateTime;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: canManageAttendance ? onOpenAttendance : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  klass['title']?.toString() ?? 'Class',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (onMorePressed != null)
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: onMorePressed,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(formatDateTime(klass['starts_at'])),
          const SizedBox(height: 6),
          Text(
            '$bookedCount/$capacity spots · ${klass['duration_minutes'] ?? 60} min',
          ),
          if (canManageAttendance) ...[
            const SizedBox(height: 8),
            const Text(
              'Tap card to manage attendance',
              style: TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          AppOutlinedButton(label: buttonLabel, onPressed: buttonAction),
        ],
      ),
    );
  }
}
