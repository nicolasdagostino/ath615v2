import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

class AppSectionChip extends StatelessWidget {
  const AppSectionChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary
            : enabled
            ? AppColors.surface(context)
            : AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: selected ? null : Border.all(color: AppColors.border(context)),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTypography.buttonLabel(context).copyWith(
          color: selected
              ? Colors.white
              : enabled
              ? AppColors.textSecondary(context)
              : AppColors.textSecondary(context).withValues(alpha: 0.55),
          letterSpacing: 0.6,
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      enabled: enabled,
      selected: selected,
      child: onTap == null || !enabled
          ? chip
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.input),
                onTap: onTap,
                child: chip,
              ),
            ),
    );
  }
}
