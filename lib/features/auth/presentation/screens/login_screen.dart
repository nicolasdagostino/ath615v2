import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/deep_link_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_form_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.signInForTesting});

  final Future<void> Function(String email, String password)? signInForTesting;

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
      await (widget.signInForTesting?.call(
            _email.text.trim(),
            _password.text,
          ) ??
          _repo.signIn(email: _email.text.trim(), password: _password.text));
      if (!mounted) return;
      context.go(pendingDeepLinkDestination.take() ?? '/');
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
      title: '',
      subtitle: appStrings.a615Tagline,
      showLogo: true,
      photographicBackground: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('login-email'),
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
            key: const ValueKey('login-password'),
            controller: _password,
            obscureText: _obscurePassword,
            style: authInputStyle(context),
            decoration:
                authFormInput(
                  context,
                  label: appStrings.authPasswordPlaceholder,
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
          AppFormSubmitButton(
            label: appStrings.authLoginButton,
            loading: _loading,
            enabled: !_loading,
            accentColor: AppColors.primary,
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
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  appStrings.authNeedHelp,
                  style: const TextStyle(color: Colors.white),
                ),
                TextButton(
                  key: const ValueKey('login-contact-us'),
                  onPressed: () => context.push('/help'),
                  child: Text(
                    appStrings.authContactUs,
                    style: const TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
