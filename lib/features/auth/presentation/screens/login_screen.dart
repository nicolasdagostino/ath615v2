import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/router/deep_link_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_form_scaffold.dart';

abstract interface class RememberedEmailStore {
  Future<String?> read();
  Future<void> save(String email);
  Future<void> clear();
}

class SharedPreferencesRememberedEmailStore implements RememberedEmailStore {
  static const key = 'remembered_login_email';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> save(String email) async =>
      (await SharedPreferences.getInstance()).setString(key, email);

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(key);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.signInForTesting, this.emailStore});

  final Future<void> Function(String email, String password)? signInForTesting;
  final RememberedEmailStore? emailStore;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _rememberEmail = false;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);
  RememberedEmailStore get _emailStore =>
      widget.emailStore ?? SharedPreferencesRememberedEmailStore();

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final remembered = await _emailStore.read();
    if (!mounted || remembered == null || remembered.isEmpty) return;
    setState(() {
      _email.text = remembered;
      _rememberEmail = true;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final normalizedEmail = _email.text.trim().toLowerCase();
      await (widget.signInForTesting?.call(normalizedEmail, _password.text) ??
          _repo.signIn(email: normalizedEmail, password: _password.text));
      if (_rememberEmail) {
        await _emailStore.save(normalizedEmail);
      } else {
        await _emailStore.clear();
      }
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
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('login-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
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
              autofillHints: const [AutofillHints.password],
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
            CheckboxListTile(
              key: const ValueKey('login-remember-email'),
              value: _rememberEmail,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              title: Text(
                appStrings.authRememberEmail,
                style: const TextStyle(color: Colors.white),
              ),
              onChanged: _loading
                  ? null
                  : (value) async {
                      final remember = value ?? false;
                      setState(() => _rememberEmail = remember);
                      if (!remember) await _emailStore.clear();
                    },
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
      ),
    );
  }
}
