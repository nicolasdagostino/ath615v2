import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_form_scaffold.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  bool get _canSubmit {
    return _fullName.text.trim().length >= 3 &&
        _email.text.trim().contains('@') &&
        _password.text.length >= 6 &&
        _password.text == _confirmPassword.text &&
        !_loading;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _loading = true);

    try {
      await _repo.signUp(
        email: _email.text.trim(),
        password: _password.text,
        fullName: _fullName.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.authAccountCreated)));

      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.signUpError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refreshSubmitState() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: appStrings.authLoginTitle,
      subtitle: appStrings.authSignUpSubtitle,
      showLogo: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.authSignUpSection.toUpperCase(),
            style: authSectionStyle(context).copyWith(fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            appStrings.authStep(1, 3).toUpperCase(),
            style: AppTypography.helper(context).copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: 0.33,
              minHeight: 6,
              backgroundColor: AppColors.border(context),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _fullName,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => _refreshSubmitState(),
            style: authInputStyle(context),
            decoration: authFormInput(
              context,
              label: appStrings.authFullName,
              icon: Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => _refreshSubmitState(),
            style: authInputStyle(context),
            decoration: authFormInput(
              context,
              label: appStrings.authEmail,
              icon: Icons.email_outlined,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscurePassword,
            onChanged: (_) => _refreshSubmitState(),
            style: authInputStyle(context),
            decoration:
                authFormInput(
                  context,
                  label: appStrings.authPassword,
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
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPassword,
            obscureText: _obscureConfirmPassword,
            onChanged: (_) => _refreshSubmitState(),
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
                      setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      );
                    },
                  ),
                ),
          ),
          const SizedBox(height: 18),
          AppFormSubmitButton(
            label: appStrings.authCreateAccount,
            loading: _loading,
            enabled: _canSubmit,
            accentColor: AppColors.primary,
            onPressed: _submit,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _loading ? null : () => context.go('/login'),
              child: Text(
                appStrings.authAlreadyHaveAccount,
                style: authLinkStyle(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
