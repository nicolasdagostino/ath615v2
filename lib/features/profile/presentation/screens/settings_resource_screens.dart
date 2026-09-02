import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_detail_header.dart';

enum SettingsResourceType { legal, documents, payments }

typedef PaymentsHistoryLoader = Future<List<Map<String, dynamic>>> Function();

class SettingsResourceScreen extends StatelessWidget {
  const SettingsResourceScreen({
    super.key,
    required this.type,
    this.paymentsHistoryLoader,
  });

  final SettingsResourceType type;
  final PaymentsHistoryLoader? paymentsHistoryLoader;

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
      body: Column(
          children: [
            AppDetailHeader(
              title: title,
              onBack: () => Navigator.of(context).maybePop(),
              leadingColor: AppColors.primary,
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
                    _RecentPayments(loader: paymentsHistoryLoader),
                  ],
                },
              ),
            ),
          ],
      ),
    );
  }
}

class _RecentPayments extends StatefulWidget {
  const _RecentPayments({this.loader});
  final PaymentsHistoryLoader? loader;

  @override
  State<_RecentPayments> createState() => _RecentPaymentsState();
}

class _RecentPaymentsState extends State<_RecentPayments> {
  late final Future<List<Map<String, dynamic>>> _rows =
      widget.loader?.call() ?? _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final response = await Supabase.instance.client.rpc(
      'list_effective_membership_requests',
      params: {'p_own': true, 'p_limit': 25},
    );
    return List<Map<String, dynamic>>.from(response).where((row) {
      return row['payment_status'] == 'paid';
    }).toList();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }
          final rows = snapshot.data ?? const [];
          if (snapshot.hasError || rows.isEmpty) {
            return _EmptyBlock(
              key: const ValueKey('payments-history-empty'),
              icon: Icons.receipt_long_outlined,
              title: appStrings.recentPayments,
              message: appStrings.noPaymentHistory,
            );
          }
          return Column(
            key: const ValueKey('payments-history-real'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appStrings.recentPayments.toUpperCase(),
                style: AppTypography.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final row in rows) _PaymentRow(row: row),
            ],
          );
        },
      );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final price = row['plan_price'];
    final currency = row['currency']?.toString().toUpperCase() ?? '';
    final amount = price == null
        ? ''
        : '${currency == 'EUR' ? '€' : '$currency '}$price';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['plan_name']?.toString() ?? appStrings.plan,
                  style: AppTypography.body(context),
                ),
                Text(
                  appStrings.paymentConfirmed,
                  style: AppTypography.bodySecondary(context),
                ),
              ],
            ),
          ),
          if (amount.isNotEmpty)
            Text(amount, style: AppTypography.body(context)),
        ],
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
