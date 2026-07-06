import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/theme/app_design_tokens.dart';

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
  const _ManagePlansSheet({required this.gymId});

  final String gymId;

  @override
  State<_ManagePlansSheet> createState() => _ManagePlansSheetState();
}

class _ManagePlansSheetState extends State<_ManagePlansSheet> {
  final _name = TextEditingController();
  final _credits = TextEditingController();
  final _price = TextEditingController();

  bool _loading = true;
  bool _saving = false;
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
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _credits.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final rows = await _client
          .from('membership_plans')
          .select(
            'id, name, plan_type, credits, price, currency, is_active, created_at',
          )
          .eq('gym_id', widget.gymId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => _plans = List<Map<String, dynamic>>.from(rows));
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

                if (planName.isEmpty) return;
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
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(AppRadii.sheet),
                      border: Border.all(
                        color: const Color(0xFF323232),
                        width: 1,
                      ),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        Text(
                          appStrings.editPlan.toUpperCase(),
                          style: _PlansText.title,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: name,
                          textCapitalization: TextCapitalization.words,
                          style: _PlansText.body.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: _plansInput(
                            appStrings.planName,
                            Icons.badge_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: planType,
                          dropdownColor: const Color(0xFF171717),
                          iconEnabledColor: const Color(0xFFABABAB),
                          style: _PlansText.body.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: _plansInput(
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
                            style: _PlansText.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _plansInput(
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
                          style: _PlansText.body.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: _plansInput(
                            appStrings.planPrice,
                            Icons.euro_rounded,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppButton(
                          label: appStrings.saveChanges,
                          loading: saving,
                          onPressed: saving ? null : save,
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
    } finally {
      name.dispose();
      credits.dispose();
      price.dispose();
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
                        color: AppColors.accent,
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

  @override
  Widget build(BuildContext context) {
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
            borderRadius: BorderRadius.circular(AppRadii.sheet),
            border: Border.all(color: const Color(0xFF323232), width: 1),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                appStrings.managePlans.toUpperCase(),
                style: _PlansText.title,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.words,
                style: _PlansText.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                decoration: _plansInput(
                  appStrings.planName,
                  Icons.badge_outlined,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _planType,
                dropdownColor: const Color(0xFF171717),
                iconEnabledColor: const Color(0xFFABABAB),
                style: _PlansText.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                decoration: _plansInput(
                  appStrings.planType,
                  Icons.tune_rounded,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'class_pack',
                    child: Text(
                      appStrings.classPack,
                      style: _PlansText.body.copyWith(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'unlimited',
                    child: Text(
                      appStrings.unlimited,
                      style: _PlansText.body.copyWith(color: Colors.white),
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
                  style: _PlansText.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: _plansInput(
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
                style: _PlansText.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                decoration: _plansInput(
                  appStrings.planPrice,
                  Icons.euro_rounded,
                ),
              ),
              const SizedBox(height: 14),
              AppButton(
                label: appStrings.createPlan,
                loading: _saving,
                onPressed: _canCreate ? _create : null,
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFB59B6A)),
                  ),
                )
              else if (_plans.isEmpty)
                Text(appStrings.noPlansYet, style: _PlansText.subtle)
              else
                ..._plans.map((plan) {
                  final active = plan['is_active'] == true;
                  final type = plan['plan_type']?.toString() == 'unlimited'
                      ? appStrings.unlimited
                      : appStrings.classPack;
                  final credits = plan['credits'];
                  final price = plan['price'];
                  final currency =
                      plan['currency']?.toString().toUpperCase() ?? 'EUR';
                  final numericPrice = price is num
                      ? price.toDouble()
                      : double.tryParse(price?.toString() ?? '');
                  final formattedAmount = numericPrice?.toStringAsFixed(2);
                  final useEuroSuffix = Localizations.localeOf(
                    context,
                  ).languageCode.startsWith('es');
                  final priceLabel = formattedAmount == null
                      ? null
                      : currency == 'EUR'
                      ? useEuroSuffix
                            ? '${formattedAmount.replaceAll('.', ',')} €'
                            : '€$formattedAmount'
                      : '$formattedAmount $currency';
                  final details = <String>[
                    type,
                    if (credits != null) '$credits ${appStrings.creditsLower}',
                  ];
                  final subtitle = details.join(' · ');

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: const Color(0xFF171717),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: () => _edit(plan),
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      plan['name']?.toString() ??
                                          appStrings.plan,
                                      style: _PlansText.rowTitle,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(subtitle, style: _PlansText.subtle),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (priceLabel != null) ...[
                                    Text(
                                      priceLabel,
                                      style: GoogleFonts.barlowCondensed(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFFB59B6A),
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                  ],
                                  _PlanStatusBadge(
                                    active: active,
                                    onTap: () => _toggle(plan),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanStatusBadge extends StatelessWidget {
  const _PlanStatusBadge({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFB59B6A) : const Color(0xFF8F96A3);
    final background = active
        ? const Color(0xFF2A2419)
        : const Color(0xFF252525);
    final label = active ? appStrings.active : appStrings.inactive;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.75), width: 1),
        ),
        child: Text(
          label.toUpperCase(),
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.8,
            height: 1,
          ),
        ),
      ),
    );
  }
}

InputDecoration _plansInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    hintStyle: _PlansText.subtle,
    labelStyle: _PlansText.subtle,
    prefixIcon: Icon(icon, color: const Color(0xFFB59B6A), size: 20),
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

class _PlansText {
  const _PlansText._();

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
    color: const Color(0xFFE5E7EB),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
    letterSpacing: 0.3,
    height: 1,
  );
}
