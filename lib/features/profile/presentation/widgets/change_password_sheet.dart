import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../auth/data/auth_repository.dart';

Future<void> showChangePasswordSheet(BuildContext context) async {
  final password = TextEditingController();
  final confirmation = TextEditingController();

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) =>
          _ChangePasswordSheet(password: password, confirmation: confirmation),
    );
  } finally {
    password.dispose();
    confirmation.dispose();
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({
    required this.password,
    required this.confirmation,
  });

  final TextEditingController password;
  final TextEditingController confirmation;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _loading = false;

  bool get _enabled {
    final password = widget.password.text.trim();
    return password.length >= 6 && password == widget.confirmation.text.trim();
  }

  Future<void> _submit() async {
    if (!_enabled || _loading) return;
    setState(() => _loading = true);
    try {
      await AuthRepository(
        Supabase.instance.client,
      ).updatePassword(widget.password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.passwordUpdated)));
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.sheetMargin),
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          border: Border.all(color: AppColors.border(context)),
          boxShadow: AppShadows.card(context),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              appStrings.profileChangePassword.toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('change-password-new'),
              controller: widget.password,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.barlow(fontWeight: FontWeight.w500),
              decoration:
                  appFormInput(
                    context,
                    icon: Icons.lock_outline_rounded,
                    accentColor: AppColors.primary,
                    hintText: appStrings.profileNewPassword,
                  ).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('change-password-confirm'),
              controller: widget.confirmation,
              obscureText: _obscureConfirmation,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.barlow(fontWeight: FontWeight.w500),
              decoration:
                  appFormInput(
                    context,
                    icon: Icons.lock_outline_rounded,
                    accentColor: AppColors.primary,
                    hintText: appStrings.profileConfirmPassword,
                  ).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                        () => _obscureConfirmation = !_obscureConfirmation,
                      ),
                      icon: Icon(
                        _obscureConfirmation
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormSubmitButton(
              label: appStrings.profileChangePassword,
              loading: _loading,
              enabled: _enabled,
              onPressed: _submit,
              accentColor: AppColors.primary,
            ),
          ],
        ),
      ),
    ),
  );
}
