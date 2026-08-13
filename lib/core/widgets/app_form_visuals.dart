import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_control_styles.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

TextStyle appFormValueStyle(BuildContext context) => AppTypography.body(
  context,
).copyWith(fontSize: 16, fontWeight: FontWeight.w500, height: 1.25);

TextStyle appFormPlaceholderStyle(BuildContext context) =>
    AppTypography.bodySecondary(
      context,
    ).copyWith(fontSize: 16, fontWeight: FontWeight.w500, height: 1.25);

class AppFormHeader extends StatelessWidget {
  const AppFormHeader({
    super.key,
    required this.title,
    required this.onClose,
    required this.accentColor,
    this.closeKey,
  });

  final String title;
  final VoidCallback onClose;
  final Color accentColor;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
        child: Row(
          children: [
            IconButton(
              key: closeKey,
              constraints: const BoxConstraints.tightFor(
                width: kMinInteractiveDimension,
                height: kMinInteractiveDimension,
              ),
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: accentColor, size: 26),
            ),
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(
              width: kMinInteractiveDimension,
              height: kMinInteractiveDimension,
            ),
          ],
        ),
      ),
    ),
  );
}

class AppFormSectionLabel extends StatelessWidget {
  const AppFormSectionLabel({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: AppTypography.sectionTitle(
      context,
    ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.45),
  );
}

InputDecoration appFormInput(
  BuildContext context, {
  required IconData icon,
  required Color accentColor,
  String hintText = '',
  String? suffix,
}) {
  final radius = BorderRadius.circular(AppRadii.input);
  return AppControlStyles.input(
    context,
    hintText: hintText,
    prefixIcon: Icon(icon, color: accentColor, size: 20),
  ).copyWith(
    hintStyle: appFormPlaceholderStyle(context),
    suffixText: suffix,
    suffixStyle: AppTypography.helper(context),
    fillColor: AppColors.surface(context),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: accentColor, width: 1.2),
    ),
  );
}

class AppFormActionField extends StatelessWidget {
  const AppFormActionField({
    super.key,
    required this.icon,
    required this.value,
    required this.onTap,
    required this.accentColor,
    this.placeholder = false,
    this.trailing = true,
  });

  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final Color accentColor;
  final bool placeholder;
  final bool trailing;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      side: BorderSide(color: AppColors.border(context)),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadii.input),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.fieldHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: placeholder
                      ? appFormPlaceholderStyle(context)
                      : appFormValueStyle(context),
                ),
              ),
              if (trailing)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary(context),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppFormSubmitButton extends StatelessWidget {
  const AppFormSubmitButton({
    super.key,
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
    required this.accentColor,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: AppSizes.buttonHeight,
    child: FilledButton(
      onPressed: loading || !enabled ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: accentColor,
        disabledBackgroundColor: AppColors.surfaceAlt(context),
        foregroundColor: Colors.white,
        disabledForegroundColor: AppColors.textSecondary(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
      ),
      child: loading
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label.toUpperCase(),
              style: AppTypography.buttonLabel(context).copyWith(
                color: enabled
                    ? Colors.white
                    : AppColors.textSecondary(context),
              ),
            ),
    ),
  );
}
