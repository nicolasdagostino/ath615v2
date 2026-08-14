import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

Future<void> showAppMessageDetailSheet({
  required BuildContext context,
  required String title,
  required String body,
  required String metadata,
  required IconData icon,
  String? actionLabel,
  VoidCallback? onAction,
  Widget? footer,
  required String closeLabel,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: 0.48),
  builder: (sheetContext) => AppMessageDetailSheet(
    title: title,
    body: body,
    metadata: metadata,
    icon: icon,
    actionLabel: actionLabel,
    onAction: onAction,
    footer: footer,
    closeLabel: closeLabel,
  ),
);

class AppMessageDetailSheet extends StatelessWidget {
  const AppMessageDetailSheet({
    super.key,
    required this.title,
    required this.body,
    required this.metadata,
    required this.icon,
    required this.closeLabel,
    this.actionLabel,
    this.onAction,
    this.footer,
  });

  final String title;
  final String body;
  final String metadata;
  final IconData icon;
  final String closeLabel;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenX,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  0,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt(context),
                        borderRadius: BorderRadius.circular(AppRadii.input),
                      ),
                      child: Icon(icon, color: AppColors.primary, size: 21),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('message-detail-close'),
                      tooltip: closeLabel,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenX,
                    AppSpacing.md,
                    AppSpacing.screenX,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.sectionTitle(context)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(metadata, style: AppTypography.helper(context)),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          body,
                          style: AppTypography.body(context).copyWith(
                            color: AppColors.textPrimary(context),
                            height: 1.45,
                          ),
                        ),
                      ],
                      if (footer != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        footer!,
                      ],
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          height: AppSizes.buttonHeight,
                          child: OutlinedButton(
                            onPressed: onAction,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.button,
                                ),
                              ),
                            ),
                            child: Text(
                              actionLabel!,
                              style: AppTypography.buttonLabel(context),
                            ),
                          ),
                        ),
                      ],
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
}
