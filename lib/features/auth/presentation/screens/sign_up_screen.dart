import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/auth_repository.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  DateTime? _birthDate;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _step = 0;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  bool get _canContinue {
    return _fullName.text.trim().length >= 3 &&
        _email.text.trim().contains('@') &&
        _password.text.length >= 6 &&
        _password.text == _confirmPassword.text;
  }

  bool get _canSubmit {
    return _canContinue &&
        _birthDate != null &&
        _phone.text.trim().length >= 6 &&
        !_loading;
  }

  String get _birthDateIso {
    final date = _birthDate;
    if (date == null) return '';

    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String get _birthDateLabel {
    final date = _birthDate;
    if (date == null) return appStrings.authBirthDate;

    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 8, now.month, now.day),
    );

    if (picked == null) return;
    setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _loading = true);

    try {
      await _repo.signUp(
        email: _email.text.trim(),
        password: _password.text,
        fullName: _fullName.text.trim(),
        phone: _phone.text.trim(),
        birthDate: _birthDateIso,
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

  void _continue() {
    if (!_canContinue) return;
    setState(() => _step = 1);
  }

  Widget _buildStepOne() {
    return Column(
      key: const ValueKey('signup-step-1'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appStrings.authStep(1, 2).toUpperCase(), style: _AuthText.subtle),
        const SizedBox(height: 8),
        Text(
          appStrings.authSignUpSection.toUpperCase(),
          style: _AuthText.section,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _refreshSubmitState(),
          style: _AuthText.body,
          decoration: _authInput(
            appStrings.authFullName,
            Icons.person_outline_rounded,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => _refreshSubmitState(),
          style: _AuthText.body,
          decoration: _authInput(appStrings.authEmail, Icons.email_outlined),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscurePassword,
          onChanged: (_) => _refreshSubmitState(),
          style: _AuthText.body,
          decoration:
              _authInput(
                appStrings.authPassword,
                Icons.lock_outline_rounded,
              ).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  color: const Color(0xFF8F96A3),
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
          style: _AuthText.body,
          decoration:
              _authInput(
                appStrings.authConfirmPassword,
                Icons.lock_outline_rounded,
              ).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  color: const Color(0xFF8F96A3),
                  onPressed: () {
                    setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    );
                  },
                ),
              ),
        ),
        const SizedBox(height: 18),
        AppButton(
          label: appStrings.authContinue,
          onPressed: _canContinue ? _continue : null,
        ),
      ],
    );
  }

  Widget _buildStepTwo() {
    return Column(
      key: const ValueKey('signup-step-2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appStrings.authStep(2, 2).toUpperCase(), style: _AuthText.subtle),
        const SizedBox(height: 8),
        Text(
          appStrings.profileHeaderTitle.toUpperCase(),
          style: _AuthText.section,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          onChanged: (_) => _refreshSubmitState(),
          style: _AuthText.body,
          decoration: _authInput(appStrings.authPhone, Icons.phone_outlined),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _pickBirthDate,
          child: InputDecorator(
            decoration: _authInput(
              appStrings.authBirthDate,
              Icons.calendar_month_rounded,
            ),
            child: Text(
              _birthDateLabel,
              style: _AuthText.body.copyWith(
                color: _birthDate == null
                    ? const Color(0xFF8F96A3)
                    : const Color(0xFF384152),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        AppButton(
          label: appStrings.authCreateAccount,
          loading: _loading,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _loading ? null : () => setState(() => _step = 0),
            child: Text(appStrings.authBack, style: _AuthText.link),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AuthShell(
      title: appStrings.authLoginTitle.toUpperCase(),
      subtitle: appStrings.authSignUpSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _step == 0 ? _buildStepOne() : _buildStepTwo(),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _loading ? null : () => context.go('/login'),
              child: Text(
                appStrings.authAlreadyHaveAccount,
                style: _AuthText.link,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthShell extends StatelessWidget {
  const _AuthShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/logo_negro.png',
                      height: 96,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(title, style: _AuthText.logo),
                  const SizedBox(height: 6),
                  Text(subtitle, style: _AuthText.subtle),
                  const SizedBox(height: 34),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
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

InputDecoration _authInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    hintStyle: _AuthText.subtle,
    labelStyle: _AuthText.subtle,
    prefixIcon: Icon(icon, color: const Color(0xFF8F96A3), size: 20),
    filled: true,
    fillColor: const Color(0xFFF4F5F7),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
  );
}

class _AuthText {
  const _AuthText._();

  static TextStyle logo = GoogleFonts.barlowCondensed(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.6,
    height: 1,
  );

  static TextStyle section = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
    letterSpacing: 0.3,
    height: 1,
  );

  static TextStyle link = GoogleFonts.barlowCondensed(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: const Color(0xFFB59B6A),
    letterSpacing: -0.1,
  );
}
