import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../booking/presentation/widgets/booking_text_styles.dart';

class WorkoutsHeader extends StatelessWidget {
  const WorkoutsHeader({
    super.key,
    required this.canManage,
    required this.onPrograms,
  });

  final bool canManage;
  final VoidCallback onPrograms;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 24, 18),
      child: Row(
        children: [
          Expanded(
            child: Text('ATHLETE LAB', style: BookingTextStyles.headerBrand),
          ),
          Text(
            appStrings.workoutsTitle.toUpperCase(),
            style: BookingTextStyles.headerMonth,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: canManage
                  ? IconButton.filledTonal(
                      tooltip: appStrings.workoutsPrograms,
                      onPressed: onPrograms,
                      icon: const Icon(Icons.category_outlined),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF4EFE6),
                        foregroundColor: const Color(0xFFB59B6A),
                        fixedSize: const Size(44, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  : const SizedBox(width: 44, height: 44),
            ),
          ),
        ],
      ),
    );
  }
}
