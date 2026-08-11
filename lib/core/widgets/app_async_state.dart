import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

enum AppAsyncStateKind { loading, empty, error }

class AppAsyncState extends StatelessWidget {
  const AppAsyncState.loading({super.key, required this.message})
    : kind = AppAsyncStateKind.loading,
      icon = null,
      actionLabel = null,
      onAction = null;

  const AppAsyncState.empty({
    super.key,
    required this.message,
    this.icon = Icons.people_outline_rounded,
  }) : kind = AppAsyncStateKind.empty,
       actionLabel = null,
       onAction = null;

  const AppAsyncState.error({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  }) : kind = AppAsyncStateKind.error,
       icon = Icons.error_outline_rounded;

  final AppAsyncStateKind kind;
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isLoading = kind == AppAsyncStateKind.loading;
    final isError = kind == AppAsyncStateKind.error;

    return Semantics(
      liveRegion: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                Icon(
                  icon,
                  size: 28,
                  color: isError
                      ? AppColors.danger
                      : AppColors.textSecondary(context),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: isError
                    ? AppTypography.error(context)
                    : AppTypography.bodySecondary(context),
              ),
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.minimumTouchTarget,
                  ),
                  child: OutlinedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
