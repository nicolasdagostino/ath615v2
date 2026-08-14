import 'package:flutter/material.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_admin_actions.dart';

class MembershipPlanRow extends StatelessWidget {
  const MembershipPlanRow({
    super.key,
    required this.plan,
    required this.onOpenActions,
    required this.onToggleActive,
  });

  final Map<String, dynamic> plan;
  final VoidCallback onOpenActions;
  final VoidCallback onToggleActive;

  String _priceLabel(BuildContext context) {
    final rawPrice = plan['price'];
    final price = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '');
    if (price == null) return '';

    final amount = price.toStringAsFixed(2);
    final currency = plan['currency']?.toString().toUpperCase() ?? 'EUR';
    final spanish = Localizations.localeOf(context).languageCode == 'es';
    if (currency == 'EUR') {
      return spanish ? '${amount.replaceAll('.', ',')} €' : '€$amount';
    }
    return '$amount $currency';
  }

  String _metadata() {
    final unlimited = plan['plan_type']?.toString() == 'unlimited';
    final credits = plan['credits'];
    final duration = plan['duration_days'] as int? ?? 30;
    final purchase = unlimited
        ? appStrings.unlimited
        : '$credits ${appStrings.creditsLower}';
    return '$purchase · ${appStrings.planDays(duration)}';
  }

  @override
  Widget build(BuildContext context) {
    final active = plan['is_active'] == true;
    final price = _priceLabel(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (plan['name']?.toString() ?? appStrings.plan).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.itemTitle(context),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(_metadata(), style: AppTypography.bodySecondary(context)),
                const SizedBox(height: AppSpacing.xs),
                InkWell(
                  onTap: onToggleActive,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.minimumTouchTarget,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.success
                                : AppColors.textSecondary(context),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          active ? appStrings.active : appStrings.inactive,
                          style: AppTypography.helper(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (price.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              price,
              style: AppTypography.itemTitle(context).copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          AppOutlinedAdminButton(
            tooltip: appStrings.editPlan,
            icon: Icons.edit_outlined,
            accentColor: AppColors.primary,
            onPressed: onOpenActions,
          ),
        ],
      ),
    );
  }
}
