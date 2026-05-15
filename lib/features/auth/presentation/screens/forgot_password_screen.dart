import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/auth_repository.dart';

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
    return _AuthShell(
      title: appStrings.authForgotTitle.toUpperCase(),
      subtitle: appStrings.authForgotSubtitle,
      onBack: () => context.pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.authResetLink.toUpperCase(),
            style: _AuthText.section,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: _AuthText.body,
            decoration: _authInput(appStrings.authEmail, Icons.email_outlined),
          ),
          const SizedBox(height: 18),
          AppButton(
            label: appStrings.authSendResetLink,
            loading: _loading,
            onPressed: _submit,
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
    this.onBack,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          children: [
            if (onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: _BackButton(onTap: onBack!),
              ),
            const SizedBox(height: 20),
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
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3EA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.chevron_left_rounded,
          size: 20,
          color: Color(0xFFB59B6A),
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
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.4,
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
}
