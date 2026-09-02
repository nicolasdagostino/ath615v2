import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_system_ui.dart';
import '../../../../core/widgets/app_detail_header.dart';

class PublicHelpScreen extends StatelessWidget {
  const PublicHelpScreen({super.key});

  void _unavailable(BuildContext context) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(appStrings.contactChannelPending)));

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: darkScreenSystemUiOverlayStyle,
    child: Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          AppDetailHeader(
            title: appStrings.publicHelpTitle,
            onBack: context.pop,
            leadingColor: AppColors.primary,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenX),
              children: [
                Text(
                  appStrings.publicHelpQuestion,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _HelpOption(
                  key: const ValueKey('help-request-demo'),
                  icon: Icons.rocket_launch_outlined,
                  label: appStrings.requestDemo,
                  onTap: () => context.push('/request-demo'),
                ),
                _HelpOption(
                  icon: Icons.support_agent,
                  label: appStrings.technicalSupport,
                  onTap: () => _unavailable(context),
                ),
                _HelpOption(
                  icon: Icons.receipt_long_outlined,
                  label: appStrings.billingHelp,
                  onTap: () => _unavailable(context),
                ),
                _HelpOption(
                  icon: Icons.chat_bubble_outline,
                  label: appStrings.otherQuestions,
                  onTap: () => _unavailable(context),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    ),
  );
}

class _HelpOption extends StatelessWidget {
  const _HelpOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: ListTile(
      onTap: onTap,
      minTileHeight: AppSizes.minimumTouchTarget,
      tileColor: const Color(0xFF171717),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        side: const BorderSide(color: Color(0xFF323232)),
      ),
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
    ),
  );
}
