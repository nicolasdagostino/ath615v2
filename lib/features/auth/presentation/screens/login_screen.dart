import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_form_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await _repo.signIn(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.loginError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: appStrings.authLoginTitle,
      subtitle: appStrings.authLoginSubtitle,
      showLogo: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.authLoginSection.toUpperCase(),
            style: authSectionStyle(context),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: authInputStyle(context),
            decoration: authFormInput(
              context,
              label: appStrings.authEmail,
              icon: Icons.email_outlined,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _password,
            obscureText: _obscurePassword,
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
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: appStrings.authLoginButton,
            loading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => context.push('/forgot-password'),
              child: Text(
                appStrings.authForgotPassword,
                style: authLinkStyle(context),
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _loading ? null : () => context.push('/signup'),
              child: Text(
                appStrings.authDontHaveAccount,
                style: authLinkStyle(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
