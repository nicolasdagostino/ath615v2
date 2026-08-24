import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';
import '../../../auth/data/auth_repository.dart';
import '../widgets/change_password_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.profileLoaderForTesting});

  @visibleForTesting
  final Future<Map<String, dynamic>?> Function()? profileLoaderForTesting;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _leavingGym = false;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile =
        await (widget.profileLoaderForTesting?.call() ?? _repo.myProfile());
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
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

  Future<void> _logout() async {
    await _repo.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _leaveGym() async {
    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: appStrings.leaveGym,
      message: appStrings.leaveGymConfirm,
      confirmLabel: appStrings.leaveGym,
      cancelLabel: appStrings.cancel,
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;

    setState(() => _leavingGym = true);
    try {
      await Supabase.instance.client.rpc('leave_current_gym');
      if (!mounted) return;
      context.go('/');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.leaveGymError(error))));
    } finally {
      if (mounted) setState(() => _leavingGym = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _profile?['role']?.toString();
    final gymId = _profile?['gym_id']?.toString();
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : SettingsContent(
                      canEditGym: role == 'admin' || role == 'owner',
                      canLeaveGym:
                          role == 'athlete' &&
                          gymId != null &&
                          gymId.isNotEmpty,
                      leavingGym: _leavingGym,
                      onAccount: () => context.push('/account'),
                      onChangePassword: () => showChangePasswordSheet(context),
                      onGymSettings: () => context.push('/gym-settings'),
                      onNotifications: () =>
                          context.push('/notification-preferences'),
                      onPreferences: () => context.push('/preferences'),
                      onLegal: () => context.push('/legal'),
                      onDocuments: () => context.push('/documents'),
                      onPayments: () => context.push('/payments'),
                      onHelp: () => _openUrl('https://athlete615.com/support'),
                      onLeaveGym: _leaveGym,
                      onLogout: _logout,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      AppSecondaryActionHeader(onBack: onBack),
      IgnorePointer(
        child: Text(
          appStrings.profileSettings.toUpperCase(),
          key: const ValueKey('settings-title'),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class SettingsContent extends StatelessWidget {
  const SettingsContent({
    super.key,
    required this.canEditGym,
    required this.canLeaveGym,
    required this.leavingGym,
    required this.onAccount,
    required this.onChangePassword,
    required this.onGymSettings,
    required this.onNotifications,
    required this.onPreferences,
    required this.onLegal,
    required this.onDocuments,
    required this.onPayments,
    required this.onHelp,
    required this.onLeaveGym,
    required this.onLogout,
  });

  final bool canEditGym;
  final bool canLeaveGym;
  final bool leavingGym;
  final VoidCallback onAccount;
  final VoidCallback onChangePassword;
  final VoidCallback onGymSettings;
  final VoidCallback onNotifications;
  final VoidCallback onPreferences;
  final VoidCallback onLegal;
  final VoidCallback onDocuments;
  final VoidCallback onPayments;
  final VoidCallback onHelp;
  final VoidCallback onLeaveGym;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('settings-scroll'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenX,
      AppSpacing.md,
      AppSpacing.screenX,
      72,
    ),
    children: [
      _SettingsRow(
        icon: Icons.person_outline_rounded,
        title: appStrings.profileAccount,
        onTap: onAccount,
      ),
      _SettingsRow(
        key: const ValueKey('settings-change-password'),
        icon: Icons.lock_outline_rounded,
        title: appStrings.profileChangePassword,
        onTap: onChangePassword,
      ),
      const SizedBox(height: AppSpacing.md),
      _SettingsRow(
        key: const ValueKey('settings-preferences'),
        icon: Icons.tune_rounded,
        title: appStrings.preferences,
        onTap: onPreferences,
      ),
      _SettingsRow(
        key: const ValueKey('settings-notifications'),
        icon: Icons.notifications_none_rounded,
        title: appStrings.notificationPreferences,
        onTap: onNotifications,
      ),
      if (canEditGym)
        _SettingsRow(
          icon: Icons.storefront_outlined,
          title: appStrings.gymInformation,
          onTap: onGymSettings,
        ),
      const SizedBox(height: AppSpacing.md),
      _SettingsRow(
        icon: Icons.help_outline_rounded,
        title: appStrings.profileHelp,
        onTap: onHelp,
      ),
      _SettingsRow(
        key: const ValueKey('settings-legal'),
        icon: Icons.gavel_outlined,
        title: appStrings.legal,
        onTap: onLegal,
      ),
      _SettingsRow(
        key: const ValueKey('settings-documents'),
        icon: Icons.folder_outlined,
        title: appStrings.documents,
        onTap: onDocuments,
      ),
      _SettingsRow(
        key: const ValueKey('settings-payments'),
        icon: Icons.credit_card_outlined,
        title: appStrings.payments,
        onTap: onPayments,
      ),
      if (canLeaveGym) ...[
        const SizedBox(height: AppSpacing.md),
        _SettingsRow(
          key: const ValueKey('settings-leave-gym'),
          icon: Icons.directions_walk_outlined,
          title: appStrings.leaveGym,
          danger: true,
          onTap: leavingGym ? null : onLeaveGym,
        ),
      ],
      const SizedBox(height: AppSpacing.xl),
      SizedBox(
        height: AppSizes.buttonHeight,
        child: OutlinedButton.icon(
          key: const ValueKey('settings-logout'),
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
          label: Text(
            appStrings.profileLogout.toUpperCase(),
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        appStrings.pick(
          'Delete account is available inside Account.',
          'Eliminar cuenta está disponible dentro de Cuenta.',
        ),
        textAlign: TextAlign.center,
        style: AppTypography.bodySecondary(context).copyWith(fontSize: 12),
      ),
    ],
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            children: [
              SizedBox(width: 38, child: Icon(icon, size: 20, color: color)),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.barlow(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
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
      ),
    );
  }
}
