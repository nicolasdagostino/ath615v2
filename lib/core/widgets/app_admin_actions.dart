import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

class AppOutlinedAdminButton extends StatelessWidget {
  const AppOutlinedAdminButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.accentColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    constraints: const BoxConstraints.tightFor(
      width: kMinInteractiveDimension,
      height: kMinInteractiveDimension,
    ),
    onPressed: onPressed,
    icon: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: 1.2),
      ),
      child: Icon(icon, color: accentColor, size: 18),
    ),
  );
}

class AppAdminAction {
  const AppAdminAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

class AppAdminActionSheet extends StatelessWidget {
  const AppAdminActionSheet({
    super.key,
    required this.actions,
    required this.onClose,
    required this.accentColor,
  });

  final List<AppAdminAction> actions;
  final VoidCallback onClose;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      color: AppColors.surface(context),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.xl,
          AppSpacing.screenX,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border(context),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final action in actions)
              InkWell(
                onTap: () {
                  onClose();
                  action.onTap();
                },
                borderRadius: BorderRadius.circular(AppRadii.input),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 68),
                  child: Row(
                    children: [
                      Icon(
                        action.icon,
                        color: action.destructive
                            ? AppColors.danger
                            : accentColor,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          action.label.toUpperCase(),
                          style: AppTypography.buttonLabel(context).copyWith(
                            color: action.destructive
                                ? AppColors.danger
                                : AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
