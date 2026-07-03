import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../auth/data/auth_repository.dart';

Color _profileHubBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF252525) : const Color(0xFFF1F2F4);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _profile;
  bool _leavingGym = false;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _repo.myProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
    });
  }

  Future<void> _leaveGym() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.border(context)),
            boxShadow: AppShadows.card(context),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                appStrings.leaveGym.toUpperCase(),
                textAlign: TextAlign.center,
                style: _SettingsText.header.copyWith(
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                appStrings.leaveGymConfirm,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary(context),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary(context),
                        side: BorderSide(color: AppColors.border(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(appStrings.cancel.toUpperCase()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(appStrings.leaveGym.toUpperCase()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _leavingGym = true);

    try {
      await Supabase.instance.client.rpc('leave_current_gym');

      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.leaveGymError(e))));
    } finally {
      if (mounted) setState(() => _leavingGym = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _profile?['role']?.toString();
    final gymId = _profile?['gym_id']?.toString();
    final canEditGym = role == 'admin' || role == 'owner';
    final canLeaveGym = role == 'athlete' && gymId != null && gymId.isNotEmpty;

    return Scaffold(
      backgroundColor: _profileHubBackground(context),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Settings',
                    style: _SettingsText.header.copyWith(
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            _SettingsMenuSection(
              children: [
                _SettingsListCard(
                  children: [
                    _SettingsMenuRow(
                      title:
                          '${appStrings.profileLanguage} · ${localeController.locale.languageCode.toUpperCase()}',
                      onTap: () {
                        final next =
                            localeController.locale.languageCode == 'en'
                            ? 'es'
                            : 'en';
                        localeController.setLanguage(next);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsListCard(
                  children: [
                    _SettingsMenuRow(
                      title:
                          '${appStrings.appearance} · ${themeController.isDark ? appStrings.dark : appStrings.light}',
                      onTap: () async {
                        await themeController.toggle();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                if (canEditGym) ...[
                  const SizedBox(height: 34),
                  _SettingsListCard(
                    children: [
                      _SettingsMenuRow(
                        title: appStrings.gymInformation,
                        onTap: () => context.push('/gym-settings'),
                      ),
                    ],
                  ),
                ],
                if (canLeaveGym) ...[
                  const SizedBox(height: 34),
                  _SettingsListCard(
                    children: [
                      _SettingsMenuRow(
                        title: appStrings.leaveGym,
                        danger: true,
                        onTap: _leavingGym ? null : _leaveGym,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsText {
  const _SettingsText._();

  static TextStyle header = GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    height: 1,
  );
}

class _SettingsMenuSection extends StatelessWidget {
  const _SettingsMenuSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      color: _profileHubBackground(context),
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 72),
      child: Column(children: children),
    );
  }
}

class _SettingsListCard extends StatelessWidget {
  const _SettingsListCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context), width: 1),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsMenuRow extends StatelessWidget {
  const _SettingsMenuRow({
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  final String title;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0,
                  height: 1.2,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}
