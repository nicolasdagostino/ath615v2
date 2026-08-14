import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_form_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await _repo.resetPassword(_email.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.authPasswordEmailSent)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.resetPasswordError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: appStrings.authForgotTitle,
      subtitle: appStrings.authForgotSubtitle,
      onBack: () => context.pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.authResetLink.toUpperCase(),
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
          const SizedBox(height: AppSpacing.lg),
          AppFormSubmitButton(
            label: appStrings.authSendResetLink,
            loading: _loading,
            enabled: !_loading,
            accentColor: AppColors.primary,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
