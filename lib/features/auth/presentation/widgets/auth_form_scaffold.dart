import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_control_styles.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';

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
                        color: AppColors.accent,
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
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle, style: AppTypography.bodySecondary(context)),
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: AppColors.border(context)),
                      boxShadow: AppShadows.card(context),
                    ),
                    child: child,
                  ),
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
  return AppControlStyles.input(
    context,
    hintText: label,
    prefixIcon: Icon(icon, color: AppColors.textSecondary(context), size: 20),
  ).copyWith(labelText: label, fillColor: AppColors.surfaceAlt(context));
}

TextStyle authSectionStyle(BuildContext context) =>
    AppTypography.sectionTitle(context).copyWith(fontSize: 18);

TextStyle authInputStyle(BuildContext context) =>
    AppTypography.body(context).copyWith(fontSize: 16);

TextStyle authLinkStyle(BuildContext context) => AppTypography.buttonLabel(
  context,
).copyWith(color: AppColors.accent, fontSize: 16);
