import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/data/auth_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _gymName = TextEditingController();

  bool _loading = false;
  Map<String, dynamic>? _profile;
  String? _gymId;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    _gymName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _repo.myProfile();
    final gymId = profile?['gym_id'] as String?;

    String gymName = '';
    if (gymId != null) {
      final gym = await Supabase.instance.client
          .from('gyms')
          .select('name')
          .eq('id', gymId)
          .maybeSingle();

      gymName = gym?['name']?.toString() ?? '';
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _gymId = gymId;
      _gymName.text = gymName;
    });
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF323232), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(title.toUpperCase(), style: _SettingsConfirmText.title),
                  Text(message, style: _SettingsConfirmText.body),
                  Row(
                    children: [
                      Expanded(
                        child: _SettingsConfirmSecondaryButton(
                          label: appStrings.cancel,
                          onTap: () => Navigator.pop(context, false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: danger
                            ? _SettingsConfirmDangerButton(
                                label: confirmLabel,
                                onTap: () => Navigator.pop(context, true),
                              )
                            : _SettingsConfirmPrimaryButton(
                                label: confirmLabel,
                                onTap: () => Navigator.pop(context, true),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return result == true;
  }

  Future<void> _openChangePasswordSheet() async {
    _password.clear();
    _confirmPassword.clear();

    var obscurePassword = true;
    var obscureConfirmPassword = true;
    var loading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF323232),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appStrings.profileChangePassword.toUpperCase(),
                        style: _SettingsText.sectionTitle,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        obscureText: obscurePassword,
                        cursorColor: const Color(0xFFB59B6A),
                        style: _SettingsText.input.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration:
                            _inputDecoration(
                              appStrings.profileNewPassword,
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                color: const Color(0xFFB59B6A),
                                onPressed: () {
                                  setSheetState(() {
                                    obscurePassword = !obscurePassword;
                                  });
                                },
                              ),
                            ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmPassword,
                        obscureText: obscureConfirmPassword,
                        cursorColor: const Color(0xFFB59B6A),
                        style: _SettingsText.input.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration:
                            _inputDecoration(
                              appStrings.profileConfirmPassword,
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                color: const Color(0xFFB59B6A),
                                onPressed: () {
                                  setSheetState(() {
                                    obscureConfirmPassword =
                                        !obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                      ),
                      const SizedBox(height: 16),
                      AppButton(
                        label: appStrings.profileChangePassword,
                        loading: loading,
                        onPressed: loading
                            ? null
                            : () async {
                                final navigator = Navigator.of(sheetContext);

                                setSheetState(() {
                                  loading = true;
                                });

                                final updated = await _changePassword();

                                if (!context.mounted) return;

                                setSheetState(() {
                                  loading = false;
                                });

                                if (mounted && updated) navigator.pop();
                              },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _changePassword() async {
    if (_password.text != _confirmPassword.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.profilePasswordsDoNotMatch)),
      );
      return false;
    }

    setState(() => _loading = true);

    try {
      await _repo.updatePassword(_password.text);
      _password.clear();
      _confirmPassword.clear();

      if (!mounted) return false;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.passwordUpdated)));

      return true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openGymNameSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF323232), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appStrings.profileGymName.toUpperCase(),
                    style: _SettingsText.sectionTitle,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _gymName,
                    cursorColor: const Color(0xFFB59B6A),
                    style: _SettingsText.input.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _inputDecoration(appStrings.profileGymName),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: appStrings.profileSaveGymName,
                    loading: _loading,
                    onPressed: () async {
                      final navigator = Navigator.of(sheetContext);
                      await _saveGymName();
                      if (mounted) navigator.pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveGymName() async {
    final gymId = _gymId;
    final name = _gymName.text.trim();

    if (gymId == null || name.isEmpty) return;

    setState(() => _loading = true);

    try {
      await Supabase.instance.client
          .from('gyms')
          .update({'name': name})
          .eq('id', gymId);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.gymNameUpdated)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.updateGymError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await _confirmAction(
      title: appStrings.profileLogout,
      message: appStrings.profileLogoutConfirm,
      confirmLabel: appStrings.profileLogout,
    );

    if (!confirmed) return;

    await _repo.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirmAction(
      title: appStrings.profileDeleteAccount,
      message: appStrings.profileDeleteConfirm,
      confirmLabel: appStrings.profileDeleteAccount,
      danger: true,
    );

    if (!confirmed) return;

    setState(() => _loading = true);
    try {
      await _repo.deleteMyAccount();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.deleteAccountError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.couldNotOpenLink)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _profile?['role']?.toString();
    final canEditGym = role == 'admin' || role == 'owner';

    return Scaffold(
      backgroundColor: const Color(0xFF252525),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: Color(0xFFB59B6A),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Settings', style: _SettingsText.header),
              ],
            ),
            const SizedBox(height: 20),
            _SettingsListCard(
              children: [
                _SettingsMenuRow(
                  icon: Icons.language_rounded,
                  title:
                      '${appStrings.profileLanguage} · ${localeController.locale.languageCode.toUpperCase()}',
                  onTap: () {
                    final next = localeController.locale.languageCode == 'en'
                        ? 'es'
                        : 'en';
                    localeController.setLanguage(next);
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsListCard(
              children: [
                if (canEditGym)
                  _SettingsMenuRow(
                    icon: Icons.business_rounded,
                    title: appStrings.profileGymName,
                    onTap: _openGymNameSheet,
                  ),
                _SettingsMenuRow(
                  icon: Icons.lock_outline_rounded,
                  title: appStrings.profileChangePassword,
                  onTap: _openChangePasswordSheet,
                ),
                _SettingsMenuRow(
                  icon: Icons.privacy_tip_outlined,
                  title: appStrings.profilePrivacyPolicy,
                  onTap: () =>
                      _openUrl('https://athlete615.com/privacy-policy'),
                ),
                _SettingsMenuRow(
                  icon: Icons.description_outlined,
                  title: appStrings.profileTerms,
                  onTap: () =>
                      _openUrl('https://athlete615.com/terms-and-conditions'),
                ),
                _SettingsMenuRow(
                  icon: Icons.help_outline_rounded,
                  title: appStrings.profileHelp,
                  onTap: () => _openUrl('https://athlete615.com/support'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsListCard(
              children: [
                _SettingsMenuRow(
                  icon: Icons.logout_rounded,
                  title: appStrings.profileLogout,
                  onTap: _logout,
                ),
                _SettingsMenuRow(
                  icon: Icons.delete_outline_rounded,
                  title: appStrings.profileDeleteAccount,
                  danger: true,
                  onTap: _deleteAccount,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlowCondensed(
      color: const Color(0xFFABABAB),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    filled: true,
    fillColor: const Color(0xFF171717),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF323232), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFB59B6A), width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF323232), width: 1),
    ),
  );
}

class _SettingsText {
  const _SettingsText._();

  static TextStyle header = GoogleFonts.barlowCondensed(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: Colors.white,
  );

  static TextStyle sectionTitle = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.8,
    height: 1.0,
  );

  static TextStyle input = GoogleFonts.barlowCondensed(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}

class _SettingsListCard extends StatelessWidget {
  const _SettingsListCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF323232), width: 1),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsMenuRow extends StatelessWidget {
  const _SettingsMenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB42318) : Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF323232)),
              ),
              child: Icon(
                icon,
                size: 20,
                color: danger
                    ? const Color(0xFFB42318)
                    : const Color(0xFFB59B6A),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.1,
                  height: 1.0,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 24,
              color: Color(0xFF8F96A3),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsConfirmText {
  const _SettingsConfirmText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle rowTitle = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );
}

class _SettingsConfirmSecondaryButton extends StatelessWidget {
  const _SettingsConfirmSecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF171717),
          side: const BorderSide(color: Color(0xFF323232)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label.toUpperCase(), style: _SettingsConfirmText.rowTitle),
      ),
    );
  }
}

class _SettingsConfirmPrimaryButton extends StatelessWidget {
  const _SettingsConfirmPrimaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF111111),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _SettingsConfirmText.rowTitle.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _SettingsConfirmDangerButton extends StatelessWidget {
  const _SettingsConfirmDangerButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFB42318),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _SettingsConfirmText.rowTitle.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
