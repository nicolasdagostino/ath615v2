import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';

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

  bool _loading = true;
  bool _saving = false;
  String _planType = 'class_pack';
  List<Map<String, dynamic>> _plans = [];

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final rows = await _client
          .from('membership_plans')
          .select('id, name, plan_type, credits, price, currency, is_active, created_at')
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

    if (name.isEmpty) return;
    if (_planType == 'class_pack' && (credits == null || credits <= 0)) return;

    setState(() => _saving = true);

    try {
      await _client.from('membership_plans').insert({
        'gym_id': widget.gymId,
        'name': name,
        'plan_type': _planType,
        'credits': _planType == 'unlimited' ? null : credits,
        'is_active': true,
      });

      _name.clear();
      _credits.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _openEditPlan(Map<String, dynamic> plan) async {
    final nameController = TextEditingController(
      text: plan['name']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: plan['price']?.toString() ?? '',
    );
    final creditsController = TextEditingController(
      text: plan['credits']?.toString() ?? '',
    );

    final isClassPack = plan['plan_type']?.toString() == 'class_pack';
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Text(appStrings.editPlan.toUpperCase(), style: _PlansText.title),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        style: _PlansText.body,
                        decoration: _plansInput(
                          appStrings.planName,
                          Icons.badge_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: _PlansText.body,
                        decoration: _plansInput(
                          'Price (€)',
                          Icons.euro_outlined,
                        ),
                      ),
                      if (isClassPack) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: creditsController,
                          keyboardType: TextInputType.number,
                          style: _PlansText.body,
                          decoration: _plansInput(
                            appStrings.credits,
                            Icons.confirmation_number_outlined,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      AppButton(
                        label: appStrings.saveChanges,
                        loading: saving,
                        onPressed: () async {
                          final name = nameController.text.trim();
                          final price = double.tryParse(
                            priceController.text.trim(),
                          );
                          final credits = int.tryParse(
                            creditsController.text.trim(),
                          );

                          if (name.isEmpty) return;
                          if (price == null || price < 0) return;
                          if (isClassPack && (credits == null || credits <= 0)) {
                            return;
                          }

                          setSheetState(() => saving = true);

                          try {
                            await _client
                                .from('membership_plans')
                                .update({
                                  'name': name,
                                  'price': price,
                                  'currency': 'EUR',
                                  if (isClassPack) 'credits': credits,
                                })
                                .eq('id', plan['id']);

                            if (!sheetContext.mounted) return;
                            Navigator.pop(sheetContext);

                            await _load();
                          } finally {
                            if (sheetContext.mounted) {
                              setSheetState(() => saving = false);
                            }
                          }
                        },
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
  }

  Future<void> _toggle(Map<String, dynamic> plan) async {
    await _client
        .from('membership_plans')
        .update({'is_active': plan['is_active'] != true})
        .eq('id', plan['id']);

    await _load();
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
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
                textCapitalization: TextCapitalization.words,
                style: _PlansText.body,
                decoration: _plansInput(
                  appStrings.planName,
                  Icons.badge_outlined,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _planType,
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
                  setState(() => _planType = value);
                },
              ),
              if (_planType == 'class_pack') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _credits,
                  keyboardType: TextInputType.number,
                  style: _PlansText.body,
                  decoration: _plansInput(
                    appStrings.credits,
                    Icons.confirmation_number_outlined,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              AppButton(
                label: appStrings.createPlan,
                loading: _saving,
                onPressed: _create,
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
                  final priceLabel = price == null ? '€-' : '€$price';

                  final subtitle = credits == null
                      ? '$priceLabel · $type · ${active ? appStrings.active : appStrings.inactive}'
                      : '$priceLabel · $type · $credits ${appStrings.creditsLower} · ${active ? appStrings.active : appStrings.inactive}';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: const Color(0xFFF7F8FA),
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
                                    plan['name']?.toString() ?? appStrings.plan,
                                    style: _PlansText.rowTitle,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(subtitle, style: _PlansText.subtle),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _openEditPlan(plan),
                              icon: const Icon(Icons.more_horiz_rounded),
                              color: const Color(0xFF384152),
                            ),
                            Switch(
                              value: active,
                              activeThumbColor: const Color(0xFFB59B6A),
                              onChanged: (_) => _toggle(plan),
                            ),
                          ],
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

InputDecoration _plansInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    hintStyle: _PlansText.subtle,
    labelStyle: _PlansText.subtle,
    prefixIcon: Icon(icon, color: const Color(0xFF8F96A3), size: 20),
    filled: true,
    fillColor: const Color(0xFFF4F5F7),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
  );
}

class _PlansText {
  const _PlansText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle rowTitle = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
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
