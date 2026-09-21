import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/password_recovery_controller.dart';
import '../widgets/auth_form_scaffold.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.controller});

  final PasswordRecoveryController? controller;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  PasswordRecoveryController get _recovery =>
      widget.controller ?? passwordRecoveryController;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final result = await _recovery.submit(
      _password.text,
      _confirmPassword.text,
    );
    if (!mounted) return;
    final message = switch (result) {
      PasswordReplacementResult.success => appStrings.passwordUpdated,
      PasswordReplacementResult.mismatch => appStrings.authPasswordsDoNotMatch,
      PasswordReplacementResult.invalidPassword =>
        appStrings.authPasswordPolicy,
      PasswordReplacementResult.unavailable => appStrings.authRecoveryInvalid,
      PasswordReplacementResult.failed => appStrings.passwordUpdateError(null),
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    if (result == PasswordReplacementResult.success) context.go('/');
  }

  Future<void> _requestAnotherLink() async {
    if (await _recovery.cancel() && mounted) context.go('/forgot-password');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _recovery,
      builder: (context, _) => AuthFormScaffold(
        title: appStrings.authSetNewPasswordTitle,
        subtitle: appStrings.authSetNewPasswordSubtitleReady,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_recovery.phase == RecoveryPhase.exchanging)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else if (!_recovery.ready)
              Text(appStrings.authRecoveryInvalid)
            else ...[
              Text(
                appStrings.authNewPasswordSection.toUpperCase(),
                style: authSectionStyle(context),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('recovery-password'),
                controller: _password,
                enabled: !_recovery.submitting,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: _obscurePassword,
                style: authInputStyle(context),
                decoration:
                    authFormInput(
                      context,
                      label: appStrings.authNewPasswordSection,
                      icon: Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        color: AppColors.textSecondary(context),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('recovery-confirmation'),
                controller: _confirmPassword,
                enabled: !_recovery.submitting,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: _obscureConfirmPassword,
                style: authInputStyle(context),
                decoration:
                    authFormInput(
                      context,
                      label: appStrings.authConfirmPassword,
                      icon: Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        color: AppColors.textSecondary(context),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
              ),
              const SizedBox(height: 18),
              if (_recovery.submitting)
                const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              else
                AppFormSubmitButton(
                  label: appStrings.authSavePassword,
                  loading: false,
                  enabled: _recovery.ready,
                  accentColor: AppColors.primary,
                  onPressed: _submit,
                ),
            ],
            if (_recovery.phase != RecoveryPhase.exchanging &&
                !_recovery.submitting)
              TextButton(
                onPressed: _requestAnotherLink,
                child: Text(appStrings.authRequestAnotherLink),
              ),
          ],
        ),
      ),
    );
  }
}
