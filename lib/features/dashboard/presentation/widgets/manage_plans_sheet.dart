import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';

Future<void> showManagePlansSheet({
  required BuildContext context,
  required String gymId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
          .select('id, name, plan_type, credits, is_active, created_at')
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

  Future<void> _toggle(Map<String, dynamic> plan) async {
    await _client
        .from('membership_plans')
        .update({'is_active': plan['is_active'] != true})
        .eq('id', plan['id']);

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              appStrings.managePlans,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: appStrings.planName),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _planType,
              decoration: InputDecoration(labelText: appStrings.planType),
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
                decoration: InputDecoration(labelText: appStrings.credits),
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
              const Center(child: CircularProgressIndicator())
            else if (_plans.isEmpty)
              Text(appStrings.noPlansYet)
            else
              ..._plans.map((plan) {
                final active = plan['is_active'] == true;
                final type = plan['plan_type']?.toString() == 'unlimited'
                    ? appStrings.unlimited
                    : appStrings.classPack;
                final credits = plan['credits'];

                return AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(plan['name']?.toString() ?? appStrings.plan),
                    subtitle: Text(
                      credits == null
                          ? '$type · ${active ? appStrings.active : appStrings.inactive}'
                          : '$type · $credits ${appStrings.creditsLower} · ${active ? appStrings.active : appStrings.inactive}',
                    ),
                    trailing: Switch(
                      value: active,
                      onChanged: (_) => _toggle(plan),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
