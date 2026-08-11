import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_design_tokens.dart';
import 'app_typography.dart';

class AppControlStyles {
  const AppControlStyles._();

  static InputDecoration input(
    BuildContext context, {
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? helperText,
    String? errorText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: BorderSide(color: AppColors.border(context)),
    );

    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTypography.bodySecondary(context),
      helperText: helperText,
      helperStyle: AppTypography.helper(context),
      errorText: errorText,
      errorStyle: AppTypography.error(context),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.surfaceAlt(context),
      constraints: const BoxConstraints(minHeight: AppSizes.fieldHeight),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
      ),
    );
  }
}
