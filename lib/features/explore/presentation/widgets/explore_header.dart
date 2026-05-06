import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../booking/presentation/widgets/booking_text_styles.dart';

class ExploreHeader extends StatelessWidget {
  const ExploreHeader({
    super.key,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Row(
        children: [
          Expanded(
            child: Text('ATHLETE LAB', style: BookingTextStyles.headerBrand),
          ),
          Text(
            appStrings.exploreTitle.toUpperCase(),
            style: BookingTextStyles.headerMonth,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton.filledTonal(
                onPressed: onOpenNotifications,
                icon: Badge(
                  isLabelVisible: unreadNotifications > 0,
                  label: Text(
                    unreadNotifications > 99
                        ? '99+'
                        : unreadNotifications.toString(),
                  ),
                  child: const Icon(Icons.notifications_outlined),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF4EFE6),
                  foregroundColor: const Color(0xFFB59B6A),
                  fixedSize: const Size(44, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
