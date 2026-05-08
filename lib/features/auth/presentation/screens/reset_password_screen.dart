import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/auth_repository.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  bool _loading = false;
  bool _sessionReady = false;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _waitForSession();
  }

  @override
  void dispose() {
    _password.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appStrings.authSessionNotReady),
        ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.passwordUpdateError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthShell(
      title: appStrings.authSetNewPasswordTitle.toUpperCase(),
      subtitle: _sessionReady
          ? appStrings.authSetNewPasswordSubtitleReady
          : appStrings.authSetNewPasswordSubtitleWaiting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(appStrings.authNewPasswordSection.toUpperCase(), style: _AuthText.section),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            style: _AuthText.body,
            decoration: _authInput(appStrings.authNewPasswordSection, Icons.lock_outline_rounded),
          ),
          const SizedBox(height: 18),
          AppButton(
            label: _sessionReady ? appStrings.authSavePassword : appStrings.authWaitingForSession,
            loading: _loading,
            onPressed: _sessionReady ? _submit : null,
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
          children: [
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
