import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_async_state.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_admin_actions.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../members/presentation/widgets/membership_plan_row.dart';

Future<void> showManagePlansSheet({
  required BuildContext context,
  required String gymId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ManagePlansSheet(gymId: gymId),
  );
}

class _ManagePlansSheet extends StatefulWidget {
  const _ManagePlansSheet({required this.gymId, this.initialPlansForTesting});

  final String gymId;
  final List<Map<String, dynamic>>? initialPlansForTesting;

  @override
  State<_ManagePlansSheet> createState() => _ManagePlansSheetState();
}

class _ManagePlansSheetState extends State<_ManagePlansSheet> {
  final _name = TextEditingController();
  final _credits = TextEditingController();
  final _price = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _showCreateForm = false;
  String? _loadError;
  String _planType = 'class_pack';

  bool get _canCreate {
    final name = _name.text.trim();
    final credits = int.tryParse(_credits.text.trim());
    final rawPrice = _price.text.trim().replaceAll(',', '.');
    final price = rawPrice.isEmpty ? null : double.tryParse(rawPrice);

    if (name.isEmpty) return false;
    if (_planType == 'class_pack' && (credits == null || credits <= 0)) {
      return false;
    }
    if (rawPrice.isNotEmpty && (price == null || price < 0)) return false;

    return true;
  }

  List<Map<String, dynamic>> _plans = [];

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    if (widget.initialPlansForTesting case final plans?) {
      _plans = plans;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _credits.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final rows = await _client
          .from('membership_plans')
          .select(
            'id, name, plan_type, credits, price, currency, duration_days, is_active, created_at',
          )
          .eq('gym_id', widget.gymId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => _plans = List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final credits = int.tryParse(_credits.text.trim());
    final rawPrice = _price.text.trim().replaceAll(',', '.');
    final price = rawPrice.isEmpty ? null : double.tryParse(rawPrice);

    if (name.isEmpty) return;
    if (_planType == 'class_pack' && (credits == null || credits <= 0)) return;
    if (rawPrice.isNotEmpty && (price == null || price < 0)) return;

    setState(() => _saving = true);

    try {
      await _client.from('membership_plans').insert({
        'gym_id': widget.gymId,
        'name': name,
        'plan_type': _planType,
        'credits': _planType == 'unlimited' ? null : credits,
        'price': price,
        'currency': 'EUR',
        'is_active': true,
      });

      _name.clear();
      _credits.clear();
      _price.clear();
      if (mounted) setState(() => _showCreateForm = false);
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> plan) async {
    final name = TextEditingController(text: plan['name']?.toString() ?? '');
    final credits = TextEditingController(
      text: plan['credits']?.toString() ?? '',
    );

    final rawPrice = plan['price'];
    final numericPrice = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '');
    final price = TextEditingController(
      text: numericPrice == null
          ? ''
          : numericPrice.toStringAsFixed(2).replaceAll('.', ','),
    );
    final durationDays = TextEditingController(
      text: (plan['duration_days'] ?? 30).toString(),
    );

    var planType = plan['plan_type']?.toString() == 'unlimited'
        ? 'unlimited'
        : 'class_pack';
    var saving = false;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> save() async {
                final planName = name.text.trim();
                final parsedCredits = int.tryParse(credits.text.trim());
                final normalizedPrice = price.text.trim().replaceAll(',', '.');
                final parsedPrice = normalizedPrice.isEmpty
                    ? null
                    : double.tryParse(normalizedPrice);
                final parsedDurationDays = int.tryParse(
                  durationDays.text.trim(),
                );

                if (planName.isEmpty) return;
                if (parsedDurationDays == null || parsedDurationDays < 1) {
                  return;
                }
                if (planType == 'class_pack' &&
                    (parsedCredits == null || parsedCredits <= 0)) {
                  return;
                }
                if (normalizedPrice.isNotEmpty &&
                    (parsedPrice == null || parsedPrice < 0)) {
                  return;
                }

                setSheetState(() => saving = true);

                try {
                  await _client
                      .from('membership_plans')
                      .update({
                        'name': planName,
                        'plan_type': planType,
                        'credits': planType == 'unlimited'
                            ? null
                            : parsedCredits,
                        'price': parsedPrice,
                        'currency': 'EUR',
                        'duration_days': parsedDurationDays,
                      })
                      .eq('id', plan['id'])
                      .eq('gym_id', widget.gymId);

                  await _load();

                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                } finally {
                  if (sheetContext.mounted) {
                    setSheetState(() => saving = false);
                  }
                }
              }

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(AppRadii.sheet),
                      border: Border.all(
                        color: AppColors.border(context),
                        width: 1,
                      ),
                      boxShadow: AppShadows.card(context),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        Text(
                          appStrings.editPlan.toUpperCase(),
                          style: _PlansText.title.copyWith(
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: name,
                          textCapitalization: TextCapitalization.words,
                          style: appFormValueStyle(context),
                          decoration: _plansInput(
                            context,
                            appStrings.planName,
                            Icons.badge_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: planType,
                          dropdownColor: AppColors.surface(context),
                          iconEnabledColor: AppColors.textSecondary(context),
                          style: appFormValueStyle(context),
                          decoration: _plansInput(
                            context,
                            appStrings.planType,
                            Icons.tune_rounded,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'class_pack',
                              child: Text(appStrings.classPack),
                            ),
                            DropdownMenuItem(
                              value: 'unlimited',
                              child: Text(appStrings.unlimited),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => planType = value);
                          },
                        ),
                        if (planType == 'class_pack') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: credits,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: appFormValueStyle(context),
                            decoration: _plansInput(
                              context,
                              appStrings.credits,
                              Icons.confirmation_number_outlined,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,.]'),
                            ),
                          ],
                          style: appFormValueStyle(context),
                          decoration: _plansInput(
                            context,
                            appStrings.planPrice,
                            Icons.euro_rounded,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: durationDays,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: appFormValueStyle(context),
                          decoration: _plansInput(
                            context,
                            appStrings.planDurationDays,
                            Icons.calendar_month_outlined,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppFormSubmitButton(
                          label: appStrings.saveChanges,
                          loading: saving,
                          enabled: !saving,
                          onPressed: save,
                          accentColor: AppColors.primary,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    Navigator.of(sheetContext).pop();
                                    await _deletePlan(plan);
                                  },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: Text(appStrings.deletePlan),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
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
    } catch (_) {
      // Keep the sheet stable if editing is dismissed or interrupted.
    }
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final planId = plan['id'];
    if (planId == null) return;

    final memberships = await _client
        .from('member_memberships')
        .select('id')
        .eq('plan_id', planId)
        .limit(1);

    final requests = await _client
        .from('membership_requests')
        .select('id')
        .eq('plan_id', planId)
        .limit(1);

    final hasMembershipHistory = List<Map<String, dynamic>>.from(
      memberships,
    ).isNotEmpty;
    final hasRequestHistory = List<Map<String, dynamic>>.from(
      requests,
    ).isNotEmpty;

    if (hasMembershipHistory || hasRequestHistory) {
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return SafeArea(
            child: Container(
              margin: EdgeInsets.all(AppSpacing.sheetMargin),
              padding: EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surface(sheetContext),
                borderRadius: BorderRadius.circular(AppRadii.sheet),
                border: Border.all(
                  color: AppColors.border(sheetContext),
                  width: 1,
                ),
                boxShadow: AppShadows.card(sheetContext),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          appStrings.planHasHistory.toUpperCase(),
                          style: _PlansText.title.copyWith(
                            color: AppColors.textPrimary(sheetContext),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appStrings.planHasHistoryMessage,
                    style: _PlansText.body.copyWith(
                      color: AppColors.textSecondary(sheetContext),
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppButton(
                    label: appStrings.close,
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    if (!mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: EdgeInsets.all(AppSpacing.sheetMargin),
            padding: EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              color: AppColors.surface(sheetContext),
              borderRadius: BorderRadius.circular(AppRadii.sheet),
              border: Border.all(
                color: AppColors.border(sheetContext),
                width: 1,
              ),
              boxShadow: AppShadows.card(sheetContext),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.danger,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        appStrings.deletePlan.toUpperCase(),
                        style: _PlansText.title.copyWith(
                          color: AppColors.textPrimary(sheetContext),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  appStrings.deletePlanMessage(
                    plan['name']?.toString() ?? appStrings.plan,
                  ),
                  style: _PlansText.body.copyWith(
                    color: AppColors.textSecondary(sheetContext),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary(sheetContext),
                          side: BorderSide(
                            color: AppColors.border(sheetContext),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(appStrings.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(appStrings.delete),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    await _client
        .from('membership_plans')
        .delete()
        .eq('id', planId)
        .eq('gym_id', widget.gymId);

    await _load();
  }

  Future<void> _toggle(Map<String, dynamic> plan) async {
    final id = plan['id'];
    final nextActive = plan['is_active'] != true;

    setState(() {
      final index = _plans.indexWhere((p) => p['id'] == id);
      if (index != -1) {
        _plans[index] = {..._plans[index], 'is_active': nextActive};
      }
    });

    try {
      await _client
          .from('membership_plans')
          .update({'is_active': nextActive})
          .eq('id', id);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        final index = _plans.indexWhere((p) => p['id'] == id);
        if (index != -1) {
          _plans[index] = {..._plans[index], 'is_active': !nextActive};
        }
      });
    }
  }

  Future<void> _openPlanActions(Map<String, dynamic> plan) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppAdminActionSheet(
        accentColor: AppColors.primary,
        onClose: () => Navigator.pop(sheetContext),
        actions: [
          AppAdminAction(
            icon: Icons.edit_outlined,
            label: appStrings.editPlan,
            onTap: () => _edit(plan),
          ),
          AppAdminAction(
            icon: Icons.delete_outline_rounded,
            label: appStrings.deletePlan,
            destructive: true,
            onTap: () => _deletePlan(plan),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(AppRadii.sheet),
            border: Border.all(color: AppColors.border(context), width: 1),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appStrings.membershipTitle.toUpperCase(),
                          style: AppTypography.itemTitle(context),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          appStrings.manageMembershipsDescription,
                          style: AppTypography.bodySecondary(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.minimumTouchTarget,
                    ),
                    child: FilledButton.icon(
                      onPressed: () =>
                          setState(() => _showCreateForm = !_showCreateForm),
                      icon: Icon(
                        _showCreateForm
                            ? Icons.close_rounded
                            : Icons.add_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      label: Text(
                        appStrings.createPlan.toUpperCase(),
                        style: AppTypography.buttonLabel(
                          context,
                        ).copyWith(color: Colors.white),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.input),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_showCreateForm) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.words,
                  style: appFormValueStyle(context),
                  decoration: _plansInput(
                    context,
                    appStrings.planName,
                    Icons.badge_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _planType,
                  dropdownColor: AppColors.surface(context),
                  iconEnabledColor: AppColors.textSecondary(context),
                  style: appFormValueStyle(context),
                  decoration: _plansInput(
                    context,
                    appStrings.planType,
                    Icons.tune_rounded,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'class_pack',
                      child: Text(
                        appStrings.classPack,
                        style: appFormValueStyle(context),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'unlimited',
                      child: Text(
                        appStrings.unlimited,
                        style: appFormValueStyle(context),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _planType = value);
                  },
                ),
                if (_planType == 'class_pack') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _credits,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: appFormValueStyle(context),
                    decoration: _plansInput(
                      context,
                      appStrings.credits,
                      Icons.confirmation_number_outlined,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _price,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  style: appFormValueStyle(context),
                  decoration: _plansInput(
                    context,
                    appStrings.planPrice,
                    Icons.euro_rounded,
                  ),
                ),
                const SizedBox(height: 14),
                AppFormSubmitButton(
                  label: appStrings.createPlan,
                  loading: _saving,
                  enabled: _canCreate,
                  onPressed: _create,
                  accentColor: AppColors.primary,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const AppCenteredLoadingIndicator()
              else if (_loadError case final error?)
                AppAsyncState.error(
                  message: error,
                  actionLabel: appStrings.retry,
                  onAction: _load,
                )
              else if (_plans.isEmpty)
                AppAsyncState.empty(
                  icon: Icons.card_membership_outlined,
                  message: appStrings.noPlansYet,
                )
              else
                ..._plans.map(
                  (plan) => MembershipPlanRow(
                    plan: plan,
                    onOpenActions: () => _openPlanActions(plan),
                    onToggleActive: () => _toggle(plan),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildManagePlansSheetForTest(List<Map<String, dynamic>> plans) {
  return _ManagePlansSheet(gymId: 'test-gym', initialPlansForTesting: plans);
}

InputDecoration _plansInput(BuildContext context, String hint, IconData icon) {
  return appFormInput(
    context,
    icon: icon,
    accentColor: AppColors.primary,
    hintText: hint,
  ).copyWith(labelText: hint, labelStyle: appFormPlaceholderStyle(context));
}

class _PlansText {
  const _PlansText._();

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1,
  );

  static const TextStyle body = TextStyle(
    color: Color(0xFFE5E7EB),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );
}
