import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';

enum SettingsResourceType { legal, documents, payments }

class SettingsResourceScreen extends StatelessWidget {
  const SettingsResourceScreen({super.key, required this.type});

  final SettingsResourceType type;

  Future<void> _open(BuildContext context, String url) async {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appStrings.couldNotOpenLink)));
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (type) {
      SettingsResourceType.legal => appStrings.legal,
      SettingsResourceType.documents => appStrings.documents,
      SettingsResourceType.payments => appStrings.payments,
    };
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Column(
          children: [
            AppSecondaryActionHeader(
              title: title,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenX,
                  AppSpacing.sm,
                  AppSpacing.screenX,
                  AppSpacing.xl,
                ),
                children: switch (type) {
                  SettingsResourceType.legal => [
                    _ResourceRow(
                      key: const ValueKey('legal-privacy'),
                      icon: Icons.shield_outlined,
                      title: appStrings.profilePrivacyPolicy,
                      onTap: () => _open(
                        context,
                        'https://athlete615.com/privacy-policy',
                      ),
                    ),
                    _ResourceRow(
                      key: const ValueKey('legal-terms'),
                      icon: Icons.description_outlined,
                      title: appStrings.profileTerms,
                      onTap: () => _open(
                        context,
                        'https://athlete615.com/terms-and-conditions',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _EmptyBlock(
                      icon: Icons.article_outlined,
                      title: appStrings.otherLegalDocuments,
                      message: appStrings.noOtherLegalDocuments,
                    ),
                  ],
                  SettingsResourceType.documents => [
                    _EmptyBlock(
                      key: const ValueKey('documents-empty'),
                      icon: Icons.folder_open_outlined,
                      title: appStrings.documents,
                      message: appStrings.noDocuments,
                    ),
                  ],
                  SettingsResourceType.payments => [
                    _EmptyBlock(
                      key: const ValueKey('payments-methods-empty'),
                      icon: Icons.credit_card_outlined,
                      title: appStrings.paymentMethods,
                      message: appStrings.noPaymentMethods,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _EmptyBlock(
                      key: const ValueKey('payments-history-empty'),
                      icon: Icons.receipt_long_outlined,
                      title: appStrings.invoicesAndHistory,
                      message: appStrings.noPaymentHistory,
                    ),
                  ],
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Icon(icon, size: 20, color: AppColors.textPrimary(context)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(title, style: AppTypography.body(context))),
          Icon(
            Icons.open_in_new_rounded,
            size: 19,
            color: AppColors.textSecondary(context),
          ),
        ],
      ),
    ),
  );
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Column(
      children: [
        Icon(icon, size: 28, color: AppColors.textSecondary(context)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTypography.body(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodySecondary(context),
        ),
      ],
    ),
  );
}
