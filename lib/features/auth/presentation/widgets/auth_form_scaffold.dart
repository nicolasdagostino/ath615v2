import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_form_visuals.dart';

class AuthFormScaffold extends StatelessWidget {
  const AuthFormScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onBack,
    this.showLogo = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onBack;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppSpacing.screenX),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (onBack != null) ...[
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: AppSizes.minimumTouchTarget,
                        height: AppSizes.minimumTouchTarget,
                      ),
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (showLogo) ...[
                    Center(
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          AppColors.isDark(context)
                              ? Colors.white
                              : Colors.black,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          'assets/images/logo_negro.png',
                          height: 96,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text(
                    title.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle, style: AppTypography.bodySecondary(context)),
                  const SizedBox(height: AppSpacing.xl),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration authFormInput(
  BuildContext context, {
  required String label,
  required IconData icon,
}) {
  return appFormInput(
    context,
    icon: icon,
    accentColor: AppColors.primary,
    hintText: label,
  );
}

TextStyle authSectionStyle(BuildContext context) =>
    AppTypography.sectionTitle(context).copyWith(fontWeight: FontWeight.w600);

TextStyle authInputStyle(BuildContext context) => appFormValueStyle(context);

TextStyle authLinkStyle(BuildContext context) => AppTypography.body(
  context,
).copyWith(color: AppColors.primary, fontWeight: FontWeight.w500);
