import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';

class MembershipStatusCard extends StatelessWidget {
  const MembershipStatusCard({
    super.key,
    required this.hasActiveMembership,
    required this.creditsRemaining,
    this.planName,
    this.expiresAt,
  });

  final bool hasActiveMembership;
  final int? creditsRemaining;
  final String? planName;
  final DateTime? expiresAt;

  bool get _hasFewCredits =>
      hasActiveMembership && creditsRemaining != null && creditsRemaining! <= 1;

  Color get _statusColor {
    if (!hasActiveMembership && creditsRemaining == 0) {
      return const Color(0xFFD99A3D);
    }
    if (!hasActiveMembership) return const Color(0xFFE84D4D);
    if (_hasFewCredits) return const Color(0xFFD99A3D);
    return const Color(0xFF22C55E);
  }

  IconData get _icon {
    if (!hasActiveMembership && creditsRemaining == 0) {
      return Icons.priority_high_rounded;
    }
    if (!hasActiveMembership) return Icons.close_rounded;
    if (_hasFewCredits) return Icons.priority_high_rounded;
    return Icons.workspace_premium_outlined;
  }

  String get _planLabel {
    final name = planName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return appStrings.membershipTitle;
  }

  String get _creditLabel {
    if (creditsRemaining == 0) {
      return appStrings.noCredits.toUpperCase();
    }
    if (!hasActiveMembership) return appStrings.membershipExpired.toUpperCase();
    if (creditsRemaining == null) return appStrings.unlimited.toUpperCase();

    final credits = creditsRemaining!;
    return credits == 1
        ? appStrings.oneCredit.toUpperCase()
        : appStrings.creditsCount(credits).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;
    final isDark = AppColors.isDark(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? color.withValues(alpha: 0.72)
              : color.withValues(alpha: 0.38),
          width: 0.9,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _planLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlowCondensed(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(context),
                letterSpacing: -0.2,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _creditLabel,
            maxLines: 1,
            style: GoogleFonts.barlowCondensed(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
