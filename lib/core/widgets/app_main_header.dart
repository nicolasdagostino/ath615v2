import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

class AppMainHeader extends StatelessWidget {
  const AppMainHeader({
    super.key,
    required this.gymName,
    required this.title,
    required this.unreadNotifications,
    required this.onOpenNotifications,
    this.subtitle,
    this.leadingAction,
  });

  final String gymName;
  final String title;
  final String? subtitle;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            AppSpacing.sm,
            AppSpacing.screenX,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gymName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.sectionTitle(
                        context,
                      ).copyWith(color: AppColors.accent),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1,
                          ),
                    ),
                    if (subtitle case final subtitle?) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.helper(context),
                      ),
                    ],
                  ],
                ),
              ),
              if (leadingAction != null) ...[
                leadingAction!,
                const SizedBox(width: AppSpacing.xs),
              ],
              AppHeaderIconButton(
                icon: Icons.notifications_outlined,
                onTap: onOpenNotifications,
                badgeCount: unreadNotifications,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppHeaderIconButton extends StatelessWidget {
  const AppHeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) => IconButton(
    constraints: const BoxConstraints.tightFor(
      width: AppSizes.minimumTouchTarget,
      height: AppSizes.minimumTouchTarget,
    ),
    style: IconButton.styleFrom(
      backgroundColor: AppColors.surface(context),
      foregroundColor: AppColors.accent,
      side: BorderSide(color: AppColors.border(context)),
    ),
    onPressed: onTap,
    icon: Badge(
      isLabelVisible: badgeCount > 0,
      backgroundColor: AppColors.danger,
      label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
      child: Icon(icon, size: 22),
    ),
  );
}
