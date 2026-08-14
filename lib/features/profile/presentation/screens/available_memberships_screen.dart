import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';

const bool stripeMembershipPaymentsEnabled = false;
const availableMembershipPlanColumns =
    'id, name, plan_type, credits, price, currency, duration_days, '
    'is_active, created_at';

enum MembershipRequestResult { sent, alreadyPending }

abstract class AvailableMembershipsService {
  Future<List<Map<String, dynamic>>> loadPlans(String type);

  Future<MembershipRequestResult> requestPlan(Map<String, dynamic> plan);

  Future<void> payByCard(Map<String, dynamic> plan);
}

class SupabaseAvailableMembershipsService
    implements AvailableMembershipsService {
  SupabaseAvailableMembershipsService(this.client);

  final SupabaseClient client;

  @override
  Future<List<Map<String, dynamic>>> loadPlans(String type) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const [];
    final response = await client.rpc(
      'list_effective_available_membership_plans',
    );
    final rows = List<Map<String, dynamic>>.from(response).map((plan) {
      return {...plan, 'id': plan['plan_id'], 'is_active': true};
    });
    return classifyAvailableMembershipPlans(
      rows
          .where((plan) => plan['name']?.toString().toLowerCase() != 'staff')
          .toList(),
      type,
    );
  }

  @override
  Future<MembershipRequestResult> requestPlan(Map<String, dynamic> plan) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    try {
      await client.rpc(
        'create_cash_membership_request',
        params: {'p_plan_id': plan['id']},
      );
      return MembershipRequestResult.sent;
    } on PostgrestException catch (error) {
      if (error.message.contains('request_pending')) {
        return MembershipRequestResult.alreadyPending;
      }
      rethrow;
    }
  }

  @override
  Future<void> payByCard(Map<String, dynamic> plan) async {
    final response = await client.functions.invoke(
      'create-membership-checkout',
      body: {'planId': plan['id']},
    );
    final data = response.data;
    final url = data is Map ? data['url']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw StateError('Missing Stripe Checkout URL');
    }
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw StateError('Could not open Stripe Checkout');
  }
}

List<Map<String, dynamic>> classifyAvailableMembershipPlans(
  List<Map<String, dynamic>> plans,
  String type,
) {
  if (type == 'dropin') {
    return plans
        .where(
          (plan) => plan['plan_type'] == 'class_pack' && plan['credits'] == 1,
        )
        .toList();
  }
  return plans
      .where(
        (plan) =>
            plan['plan_type'] == 'unlimited' ||
            (plan['plan_type'] == 'class_pack' &&
                (plan['credits'] as num?) != null &&
                (plan['credits'] as num) > 1),
      )
      .toList();
}

class AvailableMembershipsScreen extends StatefulWidget {
  const AvailableMembershipsScreen({
    super.key,
    required this.type,
    this.service,
  });

  final String type;

  @visibleForTesting
  final AvailableMembershipsService? service;

  @override
  State<AvailableMembershipsScreen> createState() =>
      _AvailableMembershipsScreenState();
}

class _AvailableMembershipsScreenState
    extends State<AvailableMembershipsScreen> {
  late final AvailableMembershipsService _service;
  List<Map<String, dynamic>> _plans = const [];
  bool _loading = true;
  String? _error;

  bool get _isSubscription => widget.type == 'subscription';

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ??
        SupabaseAvailableMembershipsService(Supabase.instance.client);
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await _service.loadPlans(widget.type);
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      debugPrint('Available memberships load failed: $error');
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openPlan(Map<String, dynamic> plan) async {
    final completed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .55),
      builder: (sheetContext) => _MembershipRequestSheet(
        plan: plan,
        isSubscription: _isSubscription,
        service: _service,
      ),
    );
    if (completed == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSubscription
        ? appStrings.getSubscription
        : appStrings.getDropIn;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Column(
          children: [
            AppSecondaryActionHeader(
              title: title,
              onBack: Navigator.of(context).pop,
            ),
            Expanded(
              child: _loading
                  ? const AppCenteredLoadingIndicator(color: AppColors.primary)
                  : _error != null
                  ? _MembershipLoadError(onRetry: _loadPlans)
                  : _plans.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.screenX),
                        child: Text(
                          _isSubscription
                              ? appStrings.noSubscriptionsAvailable
                              : appStrings.noDropInsAvailable,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySecondary(context),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('available-memberships-list'),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenX,
                        AppSpacing.lg,
                        AppSpacing.screenX,
                        AppSpacing.xl,
                      ),
                      itemCount: _plans.length,
                      separatorBuilder: (_, _) => Divider(
                        height: AppSpacing.lg,
                        thickness: .7,
                        color: AppColors.border(context),
                      ),
                      itemBuilder: (_, index) => _AvailablePlanRow(
                        plan: _plans[index],
                        onTap: () => _openPlan(_plans[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailablePlanRow extends StatelessWidget {
  const _AvailablePlanRow({required this.plan, required this.onTap});
  final Map<String, dynamic> plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('available-plan-${plan['id']}'),
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadii.input),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 92),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    (plan['name']?.toString() ?? appStrings.plan).toUpperCase(),
                    style: AppTypography.itemTitle(context),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(_planAccess(plan), style: AppTypography.body(context)),
                  if (plan['duration_days'] != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      appStrings.planDays(plan['duration_days'] as int),
                      style: AppTypography.bodySecondary(context),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _planPrice(plan),
                    style: AppTypography.body(context).copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ],
        ),
      ),
    ),
  );
}

class _MembershipRequestSheet extends StatefulWidget {
  const _MembershipRequestSheet({
    required this.plan,
    required this.isSubscription,
    required this.service,
  });
  final Map<String, dynamic> plan;
  final bool isSubscription;
  final AvailableMembershipsService service;

  @override
  State<_MembershipRequestSheet> createState() =>
      _MembershipRequestSheetState();
}

class _MembershipRequestSheetState extends State<_MembershipRequestSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _request() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.requestPlan(widget.plan);
      if (!mounted) return;
      final message = result == MembershipRequestResult.alreadyPending
          ? appStrings.membershipRequestAlreadySent
          : appStrings.membershipRequestSent;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = appStrings.membershipRequestError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      key: const ValueKey('membership-request-sheet'),
      color: AppColors.surface(context),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.lg,
          AppSpacing.screenX,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appStrings.requestMembershipTitle.toUpperCase(),
                    style: AppTypography.itemTitle(context),
                  ),
                ),
                IconButton(
                  onPressed: Navigator.of(context).pop,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              (widget.plan['name']?.toString() ?? appStrings.plan)
                  .toUpperCase(),
              style: AppTypography.itemTitle(context).copyWith(fontSize: 22),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(_planAccess(widget.plan), style: AppTypography.body(context)),
            if (widget.plan['duration_days'] != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                appStrings.planDays(widget.plan['duration_days'] as int),
                style: AppTypography.bodySecondary(context),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              _planPrice(widget.plan),
              style: AppTypography.itemTitle(
                context,
              ).copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              appStrings.requestMembershipConfirm,
              style: AppTypography.bodySecondary(context),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTypography.error(context)),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppFormSubmitButton(
              label: widget.isSubscription
                  ? appStrings.requestSubscription
                  : appStrings.requestDropIn,
              loading: _loading,
              enabled: true,
              onPressed: _request,
              accentColor: AppColors.primary,
            ),
            if (stripeMembershipPaymentsEnabled) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => widget.service.payByCard(widget.plan),
                child: Text(appStrings.payByCard.toUpperCase()),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _MembershipLoadError extends StatelessWidget {
  const _MembershipLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.screenX),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            color: AppColors.textSecondary(context),
            size: 28,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            appStrings.plansLoadError,
            key: const ValueKey('available-memberships-error-message'),
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            key: const ValueKey('available-memberships-retry'),
            onPressed: onRetry,
            child: Text(appStrings.retry.toUpperCase()),
          ),
        ],
      ),
    ),
  );
}

String _planAccess(Map<String, dynamic> plan) {
  final credits = plan['credits'];
  if (credits == null) return appStrings.unlimitedAccess;
  return credits == 1
      ? appStrings.classCredit(1)
      : appStrings.classCredits(credits as int);
}

String _planPrice(Map<String, dynamic> plan) {
  final price = plan['price'];
  if (price == null) return appStrings.priceComingSoon;
  final currency = plan['currency']?.toString().toUpperCase() ?? 'EUR';
  final symbol = currency == 'EUR' ? '€' : '$currency ';
  return '$symbol$price';
}
