import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

class AppContextActionSheet extends StatelessWidget {
  const AppContextActionSheet({
    super.key,
    required this.title,
    required this.actions,
    this.eyebrow,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.sheetMargin),
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(AppRadii.panel),
            border: Border.all(color: AppColors.border(context)),
            boxShadow: AppShadows.card(context),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                title.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              if (eyebrow != null && eyebrow!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  eyebrow!.toUpperCase(),
                  style: AppTypography.sectionTitle(
                    context,
                  ).copyWith(color: AppColors.textSecondary(context)),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(height: AppSpacing.sm),
                actions[index],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AppContextActionRow extends StatelessWidget {
  const AppContextActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final actionColor = destructive
        ? AppColors.danger
        : AppColors.textPrimary(context);

    return Material(
      color: AppColors.surfaceAlt(context),
      borderRadius: BorderRadius.circular(AppRadii.input),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.input),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.minimumTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm + AppSpacing.xxs / 2,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: destructive ? AppColors.danger : AppColors.accent,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTypography.itemTitle(
                          context,
                        ).copyWith(color: actionColor),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.helper(context),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: destructive
                      ? AppColors.danger
                      : AppColors.textSecondary(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
