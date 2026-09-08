import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/auth_repository.dart';
import '../../data/session_access_revalidator.dart';

class GymAccessDisabledScreen extends StatefulWidget {
  const GymAccessDisabledScreen({super.key, this.signOutForTesting});

  @visibleForTesting
  final Future<void> Function()? signOutForTesting;

  @override
  State<GymAccessDisabledScreen> createState() =>
      _GymAccessDisabledScreenState();
}

class _GymAccessDisabledScreenState extends State<GymAccessDisabledScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      final action =
          widget.signOutForTesting ??
          () => AuthRepository(Supabase.instance.client).signOut();
      await action();
      clearRecordedSessionAccess();
      if (mounted) context.go('/login');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenX),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        AppColors.isDark(context) ? Colors.white : Colors.black,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/images/logo_negro.png',
                        key: const ValueKey('gym-access-disabled-a615-logo'),
                        height: 54,
                        fit: BoxFit.contain,
                        semanticLabel: 'A615',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_person_outlined,
                        color: AppColors.primary,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      appStrings.gymAccessDisabledTitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.itemTitle(
                        context,
                      ).copyWith(fontSize: 28),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      appStrings.gymAccessDisabledMessage,
                      textAlign: TextAlign.center,
                      style: AppTypography.itemTitle(context),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      appStrings.gymAccessDisabledHelp,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySecondary(context),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      key: const ValueKey('gym-access-disabled-sign-out'),
                      label: appStrings.gymAccessDisabledSignOut,
                      loading: _signingOut,
                      onPressed: _signOut,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
