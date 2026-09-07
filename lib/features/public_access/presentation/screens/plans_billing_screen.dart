import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../data/help_center_repository.dart';
import '../widgets/public_request_scaffold.dart';

class PlansBillingScreen extends StatefulWidget {
  const PlansBillingScreen({super.key, this.repository});
  final HelpCenterRepository? repository;
  @override
  State<PlansBillingScreen> createState() => _PlansBillingScreenState();
}

class _PlansBillingScreenState extends State<PlansBillingScreen> {
  List<Map<String, dynamic>> plans = [];
  Map<String, dynamic>? usage, pending;
  bool loading = true, working = false;
  HelpCenterRepository get repo =>
      widget.repository ??
      SupabaseHelpCenterRepository(Supabase.instance.client);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final values = await Future.wait([
      repo.getPlans(),
      repo.getAdminPlan(),
      repo.getPendingPlanRequest(),
    ]);
    if (mounted) {
      setState(() {
        plans = values[0] as List<Map<String, dynamic>>;
        usage = values[1] as Map<String, dynamic>?;
        pending = values[2] as Map<String, dynamic>?;
        loading = false;
      });
    }
  }

  Future<void> request(String code) async {
    setState(() => working = true);
    try {
      await repo.requestPlan(code);
      await load();
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> cancel() async {
    final id = pending?['id']?.toString();
    if (id == null) return;
    setState(() => working = true);
    try {
      await repo.cancelPlanRequest(id);
      await load();
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => PublicRequestScaffold(
    title: appStrings.pick('Plans & billing', 'Planes y facturación'),
    onBack: context.pop,
    child: loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        : ListView(
            padding: const EdgeInsets.all(AppSpacing.screenX),
            children: [
              if (usage != null) ...[
                Text(
                  '${appStrings.pick('Current plan', 'Plan actual')}: ${usage!['plan_name']}',
                  key: const ValueKey('plans-current'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  usage!['active_member_limit'] == null
                      ? '${usage!['active_athlete_count']} · ${appStrings.pick('Unlimited', 'Ilimitado')}'
                      : '${usage!['active_athlete_count']} / ${usage!['active_member_limit']} · ${usage!['remaining_slots']} ${appStrings.pick('remaining', 'disponibles')}',
                  style: const TextStyle(color: Colors.white70),
                ),
                if (pending != null)
                  Card(
                    key: const ValueKey('plans-pending'),
                    child: ListTile(
                      title: Text(
                        appStrings.pick(
                          'Plan change pending',
                          'Cambio de plan pendiente',
                        ),
                      ),
                      subtitle: Text(
                        '${pending!['current_plan_code']} → ${pending!['requested_plan_code']}',
                      ),
                      trailing: TextButton(
                        onPressed: working ? null : cancel,
                        child: Text(appStrings.pick('CANCEL', 'CANCELAR')),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              ...plans.map(
                (p) => Card(
                  key: ValueKey('plan-${p['code']}'),
                  color: const Color(0xFF171717),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p['name']} · €${p['monthly_price_eur']} / ${appStrings.pick('month', 'mes')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          p['active_member_limit'] == null
                              ? appStrings.pick(
                                  'Unlimited active athletes',
                                  'Atletas activos ilimitados',
                                )
                              : appStrings.pick(
                                  'Up to ${p['active_member_limit']} active athletes',
                                  'Hasta ${p['active_member_limit']} atletas activos',
                                ),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (usage != null &&
                            usage!['plan_code'] != p['code'] &&
                            pending == null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: working
                                  ? null
                                  : () => request(p['code'].toString()),
                              child: Text(
                                appStrings.pick(
                                  'REQUEST CHANGE',
                                  'SOLICITAR CAMBIO',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                appStrings.pick(
                  'Plan changes are reviewed before being applied.',
                  'Los cambios de plan se revisan antes de aplicarse.',
                ),
                style: const TextStyle(color: Colors.white70),
              ),
              if (usage == null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton(
                    key: const ValueKey('plans-request-demo'),
                    onPressed: () => context.push('/request-demo'),
                    child: Text(
                      appStrings.pick('REQUEST A DEMO', 'SOLICITAR UNA DEMO'),
                    ),
                  ),
                ),
            ],
          ),
  );
}
