import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

Future<bool> showAppConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = true,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) => AppConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
    ),
  );
  return result == true;
}

Future<void> showAppMessageDialog({
  required BuildContext context,
  required String title,
  required String message,
  String actionLabel = 'OK',
  bool error = false,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.55),
  builder: (dialogContext) => AppConfirmationDialog(
    title: title,
    message: message,
    confirmLabel: actionLabel,
    cancelLabel: '',
    destructive: error,
    icon: error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
    showCancel: false,
  ),
);

class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.destructive = true,
    this.icon,
    this.showCancel = true,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;
  final bool showCancel;

  @override
  Widget build(BuildContext context) {
    final actionColor = destructive ? AppColors.danger : AppColors.accent;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border(context)),
            boxShadow: AppShadows.card(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: AppSizes.minimumTouchTarget,
                  height: AppSizes.minimumTouchTarget,
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                  child: Icon(
                    icon ?? Icons.delete_outline_rounded,
                    color: actionColor,
                    size: 22,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: AppTypography.bodySecondary(context)),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    if (showCancel) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(cancelLabel),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: actionColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
