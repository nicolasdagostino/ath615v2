import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

class AppSmallOutlinedButton extends StatelessWidget {
  const AppSmallOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary(context),
      disabledForegroundColor: AppColors.textSecondary(context),
      backgroundColor: AppColors.surface(context),
      side: BorderSide(color: AppColors.border(context)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
    );

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 18),
        label: Text(label, style: AppTypography.buttonLabel(context)),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label, style: AppTypography.buttonLabel(context)),
    );
  }
}
