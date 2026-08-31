import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_large_form_sheet.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';
import '../membership_request_error.dart';

const bool stripeMembershipPaymentsEnabled = false;
const availableMembershipPlanColumns =
    'id, name, plan_type, credits, price, currency, duration_days, '
    'is_active, created_at';

enum MembershipRequestResult { sent, alreadyPending }

enum MembershipPaymentChoice { card, inPerson }

class MembershipCheckoutContext {
  const MembershipCheckoutContext({
    required this.gym,
    required this.documents,
    required this.gymDocuments,
  });

  final Map<String, dynamic> gym;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> gymDocuments;

  factory MembershipCheckoutContext.fromJson(Map<String, dynamic> json) =>
      MembershipCheckoutContext(
        gym: Map<String, dynamic>.from(json['gym'] as Map? ?? const {}),
        documents: List<Map<String, dynamic>>.from(
          (json['documents'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        ),
        gymDocuments: List<Map<String, dynamic>>.from(
          (json['gymDocuments'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        ),
      );
}

abstract class AvailableMembershipsService {
  Future<List<Map<String, dynamic>>> loadPlans(String type);

  Future<MembershipRequestResult> requestPlan(
    Map<String, dynamic> plan,
    List<String> documentIds,
    List<String> gymDocumentVersionIds,
  );

  Future<void> payByCard(
    Map<String, dynamic> plan,
    List<String> documentIds,
    List<String> gymDocumentVersionIds,
  );

  Future<MembershipCheckoutContext> loadCheckoutContext(
    Map<String, dynamic> plan,
  );
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
  Future<MembershipRequestResult> requestPlan(
    Map<String, dynamic> plan,
    List<String> documentIds,
    List<String> gymDocumentVersionIds,
  ) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    try {
      await client.rpc(
        'create_consented_cash_membership_request',
        params: {
          'p_plan_id': plan['id'],
          'p_document_ids': documentIds,
          'p_gym_document_version_ids': gymDocumentVersionIds,
        },
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
  Future<void> payByCard(
    Map<String, dynamic> plan,
    List<String> documentIds,
    List<String> gymDocumentVersionIds,
  ) async {
    final response = await client.functions.invoke(
      'create-membership-checkout',
      body: {
        'planId': plan['id'],
        'documentIds': documentIds,
        'gymDocumentVersionIds': gymDocumentVersionIds,
      },
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

  @override
  Future<MembershipCheckoutContext> loadCheckoutContext(
    Map<String, dynamic> plan,
  ) async {
    final data = await client.rpc(
      'get_membership_checkout_context',
      params: {'p_plan_id': plan['id']},
    );
    return MembershipCheckoutContext.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
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
    this.reviewDocuments,
  });

  final String type;

  @visibleForTesting
  final AvailableMembershipsService? service;

  @visibleForTesting
  final Future<void> Function(BuildContext context)? reviewDocuments;

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
        _error = appStrings.plansLoadError;
        _loading = false;
      });
    }
  }

  Future<void> _openPlan(Map<String, dynamic> plan) async {
    final completed = await showAppLargeFormSheet<bool>(
      context: context,
      builder: (sheetContext) => _MembershipRequestSheet(
        plan: plan,
        isSubscription: _isSubscription,
        service: _service,
        reviewDocuments: widget.reviewDocuments,
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
    this.reviewDocuments,
  });
  final Map<String, dynamic> plan;
  final bool isSubscription;
  final AvailableMembershipsService service;
  final Future<void> Function(BuildContext context)? reviewDocuments;

  @override
  State<_MembershipRequestSheet> createState() =>
      _MembershipRequestSheetState();
}

class _MembershipRequestSheetState extends State<_MembershipRequestSheet> {
  bool _loading = false;
  bool _loadingContext = true;
  MembershipRequestErrorPresentation? _error;
  MembershipCheckoutContext? _checkout;
  MembershipPaymentChoice _payment = MembershipPaymentChoice.inPerson;
  final Set<String> _acceptedDocumentIds = {};
  final Set<String> _acceptedGymDocumentVersionIds = {};

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    try {
      final checkout = await widget.service.loadCheckoutContext(widget.plan);
      if (!mounted) return;
      setState(() {
        _checkout = checkout;
        _acceptedDocumentIds.addAll(
          checkout.documents
              .where((document) => document['accepted'] == true)
              .map((document) => document['id'].toString()),
        );
        _acceptedGymDocumentVersionIds.addAll(
          checkout.gymDocuments
              .where((document) => document['accepted'] == true)
              .map((document) => document['versionId'].toString()),
        );
        _loadingContext = false;
      });
    } catch (error) {
      debugPrint('Membership checkout context load failed: $error');
      if (!mounted) return;
      setState(() {
        _loadingContext = false;
        _error = presentMembershipRequestError(error);
      });
    }
  }

  Future<void> _reviewDocuments() async {
    if (_error?.canReviewDocuments ?? false) {
      if (widget.reviewDocuments case final review?) {
        await review(context);
      } else {
        await context.push('/documents');
      }
    }
    if (!mounted) return;
    setState(() {
      _acceptedDocumentIds.clear();
      _acceptedGymDocumentVersionIds.clear();
      _loadingContext = true;
      _error = null;
    });
    await _loadContext();
  }

  List<Map<String, dynamic>> get _requiredDocuments =>
      _checkout?.documents
          .where((document) => document['required'] == true)
          .toList() ??
      const [];

  bool get _hasRequiredConsent =>
      _requiredDocuments.every(
        (document) => _acceptedDocumentIds.contains(document['id']?.toString()),
      ) &&
      (_checkout?.gymDocuments ?? const [])
          .where((document) => document['acceptanceMode'] == 'required')
          .every(
            (document) => _acceptedGymDocumentVersionIds.contains(
              document['versionId']?.toString(),
            ),
          );

  Future<void> _request() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final documentIds = _acceptedDocumentIds.toList(growable: false);
      final gymDocumentVersionIds = _acceptedGymDocumentVersionIds.toList(
        growable: false,
      );
      if (_payment == MembershipPaymentChoice.card) {
        if (!stripeMembershipPaymentsEnabled) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = MembershipRequestErrorPresentation(
              kind: MembershipRequestErrorKind.unexpected,
              title: appStrings.membershipRequestCouldNotComplete,
              message: appStrings.cardPaymentsComingSoon,
            );
          });
          return;
        }
        await widget.service.payByCard(
          widget.plan,
          documentIds,
          gymDocumentVersionIds,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      final result = await widget.service.requestPlan(
        widget.plan,
        documentIds,
        gymDocumentVersionIds,
      );
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
      debugPrint('Membership request failed: $error');
      setState(() {
        _loading = false;
        _error = presentMembershipRequestError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      key: const ValueKey('membership-request-sheet'),
      children: [
        AppSecondaryActionHeader(
          title: appStrings.obtainMembership,
          leadingIcon: Icons.close_rounded,
          onBack: Navigator.of(context).pop,
        ),
        Expanded(
          child: _loadingContext
              ? const AppCenteredLoadingIndicator(color: AppColors.primary)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenX,
                    AppSpacing.sm,
                    AppSpacing.screenX,
                    AppSpacing.lg,
                  ),
                  children: [
                    AppFormSectionLabel(label: appStrings.plan.toUpperCase()),
                    const SizedBox(height: AppSpacing.xs),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      (widget.plan['name']?.toString() ?? appStrings.plan)
                          .toUpperCase(),
                      style: AppTypography.itemTitle(
                        context,
                      ).copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _planAccess(widget.plan),
                      style: AppTypography.body(context),
                    ),
                    if (widget.plan['duration_days'] != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        appStrings.planDays(
                          widget.plan['duration_days'] as int,
                        ),
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
                    AppFormSectionLabel(
                      label: appStrings.startDate.toUpperCase(),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      appStrings.startsWhenActivated,
                      style: AppTypography.body(context),
                    ),
                    if (_checkout != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppFormSectionLabel(label: appStrings.gymIdentityLabel),
                      const SizedBox(height: AppSpacing.xs),
                      _GymBusinessDetails(gym: _checkout!.gym),
                      const SizedBox(height: AppSpacing.lg),
                      AppFormSectionLabel(
                        label: appStrings.paymentMethod.toUpperCase(),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _PaymentChoiceRow(
                        value: _payment,
                        onChanged: (value) => setState(() => _payment = value),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _payment == MembershipPaymentChoice.card
                            ? appStrings.secureStripePayment
                            : appStrings.inPersonCheckoutExplanation,
                        style: AppTypography.bodySecondary(context),
                      ),
                      if (_checkout!.documents.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        AppFormSectionLabel(
                          label: appStrings.legal.toUpperCase(),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        for (final document in _checkout!.documents)
                          _CheckoutDocumentRow(
                            document: document,
                            accepted: _acceptedDocumentIds.contains(
                              document['id']?.toString(),
                            ),
                            onChanged: document['required'] == true
                                ? (selected) => setState(() {
                                    final id = document['id'].toString();
                                    if (selected) {
                                      _acceptedDocumentIds.add(id);
                                    } else {
                                      _acceptedDocumentIds.remove(id);
                                    }
                                  })
                                : null,
                          ),
                      ],
                      if (_checkout!.gymDocuments.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        for (final document in _checkout!.gymDocuments)
                          _GymCheckoutDocumentRow(
                            document: document,
                            accepted: _acceptedGymDocumentVersionIds.contains(
                              document['versionId']?.toString(),
                            ),
                            onChanged: document['acceptanceMode'] == 'required'
                                ? (selected) => setState(() {
                                    final id = document['versionId'].toString();
                                    if (selected) {
                                      _acceptedGymDocumentVersionIds.add(id);
                                    } else {
                                      _acceptedGymDocumentVersionIds.remove(id);
                                    }
                                  })
                                : null,
                          ),
                      ],
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!.title,
                        key: const ValueKey('membership-request-error-title'),
                        style: AppTypography.itemTitle(context),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _error!.message,
                        key: const ValueKey('membership-request-error-message'),
                        style: AppTypography.error(context),
                      ),
                      if (_error!.canReviewDocuments) ...[
                        const SizedBox(height: AppSpacing.xs),
                        TextButton(
                          key: const ValueKey('membership-review-documents'),
                          onPressed: _reviewDocuments,
                          child: Text(appStrings.reviewDocuments.toUpperCase()),
                        ),
                      ],
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    AppFormSubmitButton(
                      label: _payment == MembershipPaymentChoice.card
                          ? appStrings.continueWithStripe
                          : appStrings.requestMembership,
                      loading: _loading,
                      enabled: !_loadingContext && _hasRequiredConsent,
                      onPressed: _request,
                      accentColor: AppColors.primary,
                    ),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _GymBusinessDetails extends StatelessWidget {
  const _GymBusinessDetails({required this.gym});
  final Map<String, dynamic> gym;

  @override
  Widget build(BuildContext context) {
    final values =
        [
              gym['businessName'],
              gym['address'],
              gym['email'],
              gym['phone'],
              gym['website'],
            ]
            .map((value) => value?.toString().trim())
            .whereType<String>()
            .where((value) => value.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (gym['name'] ?? appStrings.gymIdentityLabel).toString(),
          style: AppTypography.itemTitle(context),
        ),
        for (final value in values) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(value, style: AppTypography.bodySecondary(context)),
        ],
      ],
    );
  }
}

class _PaymentChoiceRow extends StatelessWidget {
  const _PaymentChoiceRow({required this.value, required this.onChanged});
  final MembershipPaymentChoice value;
  final ValueChanged<MembershipPaymentChoice> onChanged;

  @override
  Widget build(BuildContext context) =>
      SegmentedButton<MembershipPaymentChoice>(
        key: const ValueKey('membership-payment-choice'),
        segments: [
          ButtonSegment(
            value: MembershipPaymentChoice.card,
            label: Text(appStrings.card),
            icon: const Icon(Icons.credit_card_outlined),
          ),
          ButtonSegment(
            value: MembershipPaymentChoice.inPerson,
            label: Text(appStrings.payInPerson),
            icon: const Icon(Icons.storefront_outlined),
          ),
        ],
        selected: {value},
        showSelectedIcon: false,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textPrimary(context),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.surface(context),
          ),
        ),
        onSelectionChanged: (selected) => onChanged(selected.single),
      );
}

class _CheckoutDocumentRow extends StatelessWidget {
  const _CheckoutDocumentRow({
    required this.document,
    required this.accepted,
    required this.onChanged,
  });
  final Map<String, dynamic> document;
  final bool accepted;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final required = document['required'] == true;
    final type = document['type']?.toString();
    final title = switch (type) {
      'terms' => appStrings.acceptTerms,
      'waiver' => appStrings.acceptWaiver,
      'sales_refund' => appStrings.acceptSalesRefund,
      _ => appStrings.profilePrivacyPolicy,
    };
    return Padding(
      key: ValueKey('checkout-document-$type'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (required)
            Checkbox(
              key: ValueKey('checkout-document-toggle-$type'),
              value: accepted,
              activeColor: AppColors.primary,
              onChanged: (value) => onChanged?.call(value ?? false),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse(document['url'].toString()),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.body(
                        context,
                      ).copyWith(color: AppColors.primary),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      appStrings.documentVersion(
                        document['version']?.toString() ?? '',
                      ),
                      style: AppTypography.bodySecondary(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GymCheckoutDocumentRow extends StatelessWidget {
  const _GymCheckoutDocumentRow({
    required this.document,
    required this.accepted,
    required this.onChanged,
  });
  final Map<String, dynamic> document;
  final bool accepted;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final required = document['acceptanceMode'] == 'required';
    return Padding(
      key: ValueKey('checkout-gym-document-${document['versionId']}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (required)
            Checkbox(
              value: accepted,
              activeColor: AppColors.primary,
              onChanged: document['accepted'] == true
                  ? null
                  : (value) => onChanged?.call(value ?? false),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document['title']?.toString() ?? appStrings.documents,
                  style: AppTypography.body(
                    context,
                  ).copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  document['body']?.toString() ?? '',
                  style: AppTypography.bodySecondary(context),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  appStrings.documentVersion(
                    document['versionNumber']?.toString() ?? '',
                  ),
                  style: AppTypography.helper(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
