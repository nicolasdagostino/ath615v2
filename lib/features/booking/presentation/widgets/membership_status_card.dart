import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'booking_text_styles.dart';

class MembershipStatusCard extends StatelessWidget {
  const MembershipStatusCard({
    super.key,
    required this.hasActiveMembership,
    required this.creditsRemaining,
  });

  final bool hasActiveMembership;
  final int? creditsRemaining;

  @override
  Widget build(BuildContext context) {
    final label = hasActiveMembership
        ? creditsRemaining == null
              ? '${appStrings.membershipTitle} ${appStrings.active.toLowerCase()} · ${appStrings.unlimited}'
              : '${appStrings.membershipTitle} ${appStrings.active.toLowerCase()} · $creditsRemaining ${appStrings.creditsLower}'
        : appStrings.bookingActiveMembershipRequiredToBook;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFFF4EFE6),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              hasActiveMembership
                  ? Icons.workspace_premium_outlined
                  : Icons.lock_outline,
              color: hasActiveMembership
                  ? const Color(0xFF149651)
                  : const Color(0xFFB69B63),
              size: 34,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              label,
              style: BookingTextStyles.membership.copyWith(
                color: hasActiveMembership
                    ? const Color(0xFF149651)
                    : const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
