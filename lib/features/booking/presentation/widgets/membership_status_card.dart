import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';

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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF4EFE6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              hasActiveMembership
                  ? Icons.workspace_premium_outlined
                  : Icons.lock_outline,
              color: hasActiveMembership
                  ? const Color(0xFF149651)
                  : const Color(0xFFB69B63),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: hasActiveMembership
                    ? const Color(0xFF149651)
                    : const Color(0xFFB45309),
                fontSize: 16,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
