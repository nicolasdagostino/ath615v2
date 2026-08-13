import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_form_scaffold.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = false;
  bool _sessionReady = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _waitForSession();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _waitForSession() async {
    for (var i = 0; i < 20; i++) {
      if (Supabase.instance.client.auth.currentSession != null) {
        if (mounted) setState(() => _sessionReady = true);
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (mounted) setState(() => _sessionReady = false);
  }

  Future<void> _submit() async {
    if (!_sessionReady) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.authSessionNotReady)));
      return;
    }

    if (_password.text != _confirmPassword.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.authPasswordsDoNotMatch)),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await _repo.updatePassword(_password.text);

      if (!mounted) return;

      context.go('/');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.passwordUpdateError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: appStrings.authSetNewPasswordTitle,
      subtitle: _sessionReady
          ? appStrings.authSetNewPasswordSubtitleReady
          : appStrings.authSetNewPasswordSubtitleWaiting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.authNewPasswordSection.toUpperCase(),
            style: authSectionStyle(context),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
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
            controller: _confirmPassword,
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
          AppButton(
            label: _sessionReady
                ? appStrings.authSavePassword
                : appStrings.authWaitingForSession,
            loading: _loading,
            onPressed: _sessionReady ? _submit : null,
          ),
        ],
      ),
    );
  }
}
