import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/data/auth_repository.dart';

class OwnerGymSummary {
  const OwnerGymSummary(this.data);
  final Map<String, dynamic> data;
  String get id => data['gym_id'].toString();
  String get name => data['gym_name']?.toString() ?? '';
  String get status => data['lifecycle_status']?.toString() ?? 'active';
  DateTime? get createdAt =>
      DateTime.tryParse(data['created_at']?.toString() ?? '');
  DateTime? get lastActivityAt =>
      DateTime.tryParse(data['last_activity_at']?.toString() ?? '');
  int count(String key) => (data[key] as num?)?.toInt() ?? 0;
  String get saasPlanName => data['saas_plan_name']?.toString() ?? 'FREE';
  int get saasMonthlyPrice =>
      (data['saas_monthly_price_eur'] as num?)?.toInt() ?? 0;
  int? get saasLimit => (data['saas_active_member_limit'] as num?)?.toInt();
  int get saasAthletes => count('saas_active_athlete_count');
  int get inactiveAthletes => count('inactive_athlete_count');
  double? get capacityPercent => (data['capacity_percent'] as num?)?.toDouble();
  int get databaseRecords => count('database_record_count');
  double get databaseShare =>
      (data['database_record_share_percent'] as num?)?.toDouble() ?? 0;
  Map<String, dynamic>? get pendingRequest =>
      data['pending_plan_request'] is Map
      ? Map<String, dynamic>.from(data['pending_plan_request'] as Map)
      : null;
  bool get saasLimitReached => data['saas_limit_reached'] == true;
  bool get saasOverLimit => data['saas_over_limit'] == true;
  String get saasUsageLabel => saasLimit == null
      ? '$saasAthletes ${appStrings.pick('athletes', 'atletas')} · ${appStrings.pick('Unlimited', 'Ilimitado')}'
      : '$saasAthletes / $saasLimit ${appStrings.pick('athletes', 'atletas')}${saasOverLimit
            ? ' · ${appStrings.pick('Over limit', 'Por encima del límite')}'
            : saasLimitReached
            ? ' · ${appStrings.pick('Limit reached', 'Límite alcanzado')}'
            : ''}';
  String get stripeLabel {
    if ((data['stripe_account_id']?.toString() ?? '').isEmpty) {
      return appStrings.stripeNotConnected;
    }
    if (data['stripe_onboarding_complete'] != true ||
        data['stripe_charges_enabled'] != true) {
      return appStrings.stripeSetupPending;
    }
    return appStrings.stripePaymentsEnabled;
  }
}

class OwnerScreen extends StatefulWidget {
  const OwnerScreen({super.key});
  @override
  State<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<OwnerScreen> {
  final _gymName = TextEditingController();
  final _inviteName = TextEditingController();
  final _inviteEmail = TextEditingController();
  final _client = Supabase.instance.client;
  List<OwnerGymSummary> _gyms = const [];
  List<Map<String, dynamic>> _planRequests = const [];
  Map<String, dynamic> _summary = const {};
  bool _loading = true, _working = false;
  String? _error;
  String _filter = 'active';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gymName.dispose();
    _inviteName.dispose();
    _inviteEmail.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final payload = Map<String, dynamic>.from(
        await _client.rpc('get_platform_owner_dashboard_v2') as Map,
      );
      final gyms = List<Map<String, dynamic>>.from(payload['gyms'] as List);
      if (!mounted) return;
      setState(() {
        _gyms = gyms.map(OwnerGymSummary.new).toList();
        _planRequests = gyms
            .where((gym) => gym['pending_plan_request'] is Map)
            .map(
              (gym) =>
                  Map<String, dynamic>.from(gym['pending_plan_request'] as Map),
            )
            .toList();
        _summary = Map<String, dynamic>.from(payload['summary'] as Map);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = appStrings.pick(
            'The Owner dashboard could not be loaded.',
            'No se pudo cargar el dashboard Owner.',
          );
        });
      }
    }
  }

  Future<void> _reviewPlanRequest(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    try {
      await _client.rpc(
        'platform_review_saas_plan_change',
        params: {
          'p_request_id': request['id'],
          'p_approve': approve,
          'p_rejection_reason': null,
        },
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      final capacity = error.toString().contains('saas_plan_capacity_too_low');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            capacity
                ? appStrings.pick(
                    'The gym now has too many active athletes for that plan.',
                    'El gimnasio ahora tiene demasiados atletas activos para ese plan.',
                  )
                : appStrings.pick(
                    'The request could not be reviewed.',
                    'No se pudo revisar la solicitud.',
                  ),
          ),
        ),
      );
    }
  }

  void _openDetail(OwnerGymSummary gym) => context.push('/owner/gym/${gym.id}');

  Future<void> _create() async {
    if (_gymName.text.trim().isEmpty) return;
    setState(() => _working = true);
    try {
      await _client.rpc(
        'create_gym',
        params: {'gym_name': _gymName.text.trim()},
      );
      _gymName.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appStrings.pick('Gym created', 'Gimnasio creado')),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appStrings.pick(
                'The gym could not be created.',
                'No se pudo crear el gimnasio.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _invite(OwnerGymSummary gym) async {
    _inviteName.clear();
    _inviteEmail.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          appStrings.pick('Invite administrator', 'Invitar administrador'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _inviteName,
              decoration: InputDecoration(
                labelText: appStrings.pick('Full name', 'Nombre completo'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _inviteEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(appStrings.cancel),
          ),
          FilledButton(
            onPressed: () async {
              if (_inviteEmail.text.trim().isEmpty) return;
              await _client.functions.invoke(
                'owner-invite-admin',
                body: {
                  'gym_id': gym.id,
                  'email': _inviteEmail.text.trim(),
                  'full_name': _inviteName.text.trim(),
                },
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      appStrings.pick('Invitation sent', 'Invitación enviada'),
                    ),
                  ),
                );
              }
            },
            child: Text(appStrings.pick('Invite', 'Invitar')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _gyms
        .where((gym) => _filter == 'all' || gym.status == _filter)
        .toList();
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(appStrings.pick('OWNER DASHBOARD', 'DASHBOARD OWNER')),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthRepository(_client).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenX),
          children: [
            OwnerDashboardKpis(summary: _summary),
            const SizedBox(height: AppSpacing.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['all', 'active', 'suspended', 'archived']
                    .map(
                      (status) => Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: ChoiceChip(
                          label: Text(_ownerStatusLabel(status).toUpperCase()),
                          selected: _filter == status,
                          selectedColor: AppColors.primary,
                          onSelected: (_) => setState(() => _filter = status),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_planRequests.isNotEmpty) ...[
              Text(
                '${appStrings.pick('PLAN REQUESTS', 'SOLICITUDES DE PLAN')} (${_planRequests.length})',
                key: const ValueKey('owner-plan-requests-title'),
                style: AppTypography.sectionTitle(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._planRequests.map(
                (request) => OwnerPlanRequestCard(
                  request: request,
                  onApprove: () => _reviewPlanRequest(request, true),
                  onReject: () => _reviewPlanRequest(request, false),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            OwnerAttentionPanel(gyms: _gyms),
            const SizedBox(height: AppSpacing.md),
            Text(
              appStrings.pick('GYM CUSTOMERS', 'GIMNASIOS'),
              key: const ValueKey('owner-gym-count'),
              style: AppTypography.sectionTitle(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: AppColors.danger))
            else
              ...visible.map(
                (gym) => OwnerGymCustomerCard(
                  gym: gym,
                  onTap: () => _openDetail(gym),
                  onInvite: () => _invite(gym),
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              appStrings.pick('CREATE GYM', 'CREAR GIMNASIO'),
              style: AppTypography.sectionTitle(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _gymName,
              decoration: InputDecoration(
                labelText: appStrings.pick('Gym name', 'Nombre del gimnasio'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: appStrings.pick('Create gym', 'Crear gimnasio'),
              loading: _working,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerPlanRequestCard extends StatelessWidget {
  const OwnerPlanRequestCard({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onReject,
  });
  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('owner-plan-request-${request['id']}'),
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      border: Border.all(color: AppColors.border(context)),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request['gym_name']?.toString() ?? '',
          style: AppTypography.itemTitle(context),
        ),
        Text(
          '${request['current_plan_name']} → ${request['requested_plan_name']}',
        ),
        Text(
          '${request['active_athlete_count']} ${appStrings.pick('active athletes', 'atletas activos')} · €${request['current_price_eur']} → €${request['requested_price_eur']} / ${appStrings.pick('month', 'mes')}',
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: onReject,
              child: Text(appStrings.pick('REJECT', 'RECHAZAR')),
            ),
            FilledButton(
              onPressed: onApprove,
              child: Text(appStrings.pick('APPROVE', 'APROBAR')),
            ),
          ],
        ),
      ],
    ),
  );
}

String _ownerStatusLabel(String status) => switch (status) {
  'active' => appStrings.pick('Active', 'Activo'),
  'suspended' => appStrings.pick('Suspended', 'Suspendido'),
  'archived' => appStrings.pick('Archived', 'Archivado'),
  _ => appStrings.pick('All', 'Todos'),
};

class OwnerDashboardKpis extends StatelessWidget {
  const OwnerDashboardKpis({super.key, required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, int)>[
      (
        Icons.business_rounded,
        appStrings.pick('Active gyms', 'Gimnasios activos'),
        (summary['active_gym_count'] as num?)?.toInt() ?? 0,
      ),
      (
        Icons.groups_rounded,
        appStrings.pick('Active athletes', 'Atletas activos'),
        (summary['active_athlete_count'] as num?)?.toInt() ?? 0,
      ),
      (
        Icons.swap_horiz_rounded,
        appStrings.pick('Plan requests', 'Solicitudes de plan'),
        (summary['pending_plan_request_count'] as num?)?.toInt() ?? 0,
      ),
      (
        Icons.pause_circle_outline_rounded,
        appStrings.pick('Suspended gyms', 'Gimnasios suspendidos'),
        (summary['suspended_gym_count'] as num?)?.toInt() ?? 0,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: Container(
                    key: ValueKey('owner-kpi-${item.$2}'),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      border: Border.all(color: AppColors.border(context)),
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.$1, color: AppColors.primary, size: 20),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${item.$3}',
                          style: AppTypography.sectionTitle(context),
                        ),
                        Text(
                          item.$2,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class OwnerAttentionPanel extends StatelessWidget {
  const OwnerAttentionPanel({super.key, required this.gyms});
  final List<OwnerGymSummary> gyms;

  @override
  Widget build(BuildContext context) {
    final attention = gyms.where(
      (gym) =>
          gym.pendingRequest != null ||
          (gym.capacityPercent ?? 0) >= 90 ||
          gym.status != 'active',
    );
    if (attention.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('owner-attention-panel'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.pick('ATTENTION', 'ATENCIÓN'),
            style: AppTypography.sectionTitle(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...attention.map((gym) {
            final reason = gym.pendingRequest != null
                ? appStrings.pick(
                    'plan request pending',
                    'solicitud de plan pendiente',
                  )
                : gym.status != 'active'
                ? _ownerStatusLabel(gym.status)
                : gym.saasOverLimit
                ? appStrings.pick('over member limit', 'supera el límite')
                : gym.saasLimitReached
                ? appStrings.pick('member limit reached', 'límite alcanzado')
                : appStrings.pick(
                    'member capacity at ${gym.capacityPercent?.toStringAsFixed(0)}%',
                    'capacidad al ${gym.capacityPercent?.toStringAsFixed(0)}%',
                  );
            return Text('• ${gym.name} · $reason');
          }),
        ],
      ),
    );
  }
}

class OwnerGymCustomerCard extends StatelessWidget {
  const OwnerGymCustomerCard({
    super.key,
    required this.gym,
    required this.onTap,
    required this.onInvite,
  });
  final OwnerGymSummary gym;
  final VoidCallback onTap, onInvite;
  @override
  Widget build(BuildContext context) {
    final percent = gym.capacityPercent;
    return Container(
      key: ValueKey('owner-gym-card-${gym.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  gym.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.itemTitle(context),
                ),
              ),
              _OwnerStatusPill(status: gym.status),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            gym.saasPlanName,
            style: AppTypography.sectionTitle(
              context,
            ).copyWith(color: AppColors.primary),
          ),
          Text(gym.saasUsageLabel),
          if (percent != null) ...[
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(
              value: (percent / 100).clamp(0, 1),
              color: AppColors.primary,
              backgroundColor: AppColors.surfaceAlt(context),
            ),
            Text('${percent.toStringAsFixed(0)}% capacity'),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              Text('${gym.count('admin_count')} admins'),
              Text('${gym.count('coach_count')} coaches'),
              Text(
                '${gym.count('active_membership_count')} ${appStrings.pick('active memberships', 'membresías activas')}',
              ),
            ],
          ),
          Text('Stripe: ${gym.stripeLabel}'),
          if (gym.pendingRequest != null)
            Text(
              appStrings.pick(
                'Plan change pending',
                'Cambio de plan pendiente',
              ),
              style: const TextStyle(color: AppColors.primary),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              IconButton(
                tooltip: appStrings.pick(
                  'Invite administrator',
                  'Invitar administrador',
                ),
                icon: const Icon(
                  Icons.person_add_alt_1,
                  color: AppColors.primary,
                ),
                onPressed: onInvite,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(appStrings.pick('VIEW GYM', 'VER GIMNASIO')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnerStatusPill extends StatelessWidget {
  const _OwnerStatusPill({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: status == 'active'
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.surfaceAlt(context),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      _ownerStatusLabel(status).toUpperCase(),
      style: AppTypography.buttonLabel(context),
    ),
  );
}

class OwnerGymDetailScreen extends StatefulWidget {
  const OwnerGymDetailScreen({super.key, required this.gymId});
  final String gymId;
  @override
  State<OwnerGymDetailScreen> createState() => _OwnerGymDetailScreenState();
}

class _OwnerGymDetailScreenState extends State<OwnerGymDetailScreen> {
  final _client = Supabase.instance.client;
  OwnerGymSummary? _gym;
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _pendingPlanRequest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = Map<String, dynamic>.from(
        await _client.rpc(
              'get_platform_gym_crm_v2',
              params: {'p_gym_id': widget.gymId},
            )
            as Map,
      );
      if (mounted) {
        setState(() {
          _detail = row;
          _gym = OwnerGymSummary(row);
          _pendingPlanRequest = row['pending_plan_request'] is Map
              ? Map<String, dynamic>.from(row['pending_plan_request'] as Map)
              : null;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = appStrings.pick(
            'The gym customer record could not be loaded.',
            'No se pudo cargar la ficha del gimnasio.',
          );
        });
      }
    }
  }

  Future<void> _openContact(String scheme, String value) async {
    final uri = Uri(scheme: scheme, path: value);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appStrings.pick(
              'The contact action could not be opened.',
              'No se pudo abrir la acción de contacto.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _reviewPending(bool approve) async {
    final request = _pendingPlanRequest;
    if (request == null) return;
    try {
      await _client.rpc(
        'platform_review_saas_plan_change',
        params: {
          'p_request_id': request['id'],
          'p_approve': approve,
          'p_rejection_reason': null,
        },
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      final capacity = error.toString().contains('saas_plan_capacity_too_low');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            capacity
                ? appStrings.pick(
                    'The gym now has too many active athletes for that plan.',
                    'El gimnasio ahora tiene demasiados atletas activos para ese plan.',
                  )
                : appStrings.pick(
                    'The plan request could not be reviewed.',
                    'No se pudo revisar la solicitud de plan.',
                  ),
          ),
        ),
      );
    }
  }

  Future<void> _setStatus(String status) async {
    final gym = _gym;
    if (gym == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(_ownerStatusLabel(status)),
            content: Text(
              appStrings.pick(
                'The gym data and history will be preserved.',
                'Los datos y el historial del gimnasio se conservarán.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(appStrings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(appStrings.pick('Confirm', 'Confirmar')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _client.rpc(
      'platform_set_gym_status',
      params: {'p_gym_id': gym.id, 'p_status': status},
    );
    await _load();
  }

  Future<void> _enterAdmin() async {
    final gym = _gym;
    if (gym == null) return;
    await _client.rpc(
      'select_owner_effective_gym',
      params: {'p_gym_id': gym.id},
    );
    if (mounted) context.go('/app?section=panel&ownerInspection=true');
  }

  Future<void> _changeSaasPlan() async {
    final gym = _gym;
    if (gym == null) return;
    final plans = List<Map<String, dynamic>>.from(
      await _client
          .from('saas_plans')
          .select('code,name,active_member_limit')
          .eq('is_active', true)
          .order('sort_order'),
    );
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(appStrings.pick('SaaS plan', 'Plan SaaS')),
        children: plans
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(c, p['code'].toString()),
                child: Text(
                  p['active_member_limit'] == null
                      ? p['name'].toString()
                      : '${p['name']} · ${p['active_member_limit']}',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null) return;
    await _client.rpc(
      'platform_set_gym_saas_subscription',
      params: {
        'p_gym_id': gym.id,
        'p_plan_code': selected,
        'p_override_member_limit': null,
      },
    );
    await _load();
  }

  Future<void> _delete() async {
    final gym = _gym;
    if (gym == null) return;
    final eligibility = Map<String, dynamic>.from(
      await _client.rpc(
            'platform_gym_delete_eligibility',
            params: {'p_gym_id': gym.id},
          )
          as Map,
    );
    if (!mounted) return;
    if (eligibility['can_delete'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appStrings.pick(
              'This gym contains protected financial, Stripe, or legal audit data.',
              'Este gimnasio contiene datos financieros, Stripe o legales protegidos.',
            ),
          ),
        ),
      );
      return;
    }
    final controller = TextEditingController();
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('${appStrings.pick('Delete', 'Eliminar')} ${gym.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appStrings.pick(
                    'This permanently deletes classes, bookings, memberships and gym configuration. Type the gym name to confirm.',
                    'Esta acción elimina permanentemente clases, reservas, membresías y configuración. Escribe el nombre del gimnasio para confirmar.',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: gym.name),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(appStrings.cancel),
              ),
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (c, value, child) => FilledButton(
                  onPressed: controller.text == gym.name
                      ? () => Navigator.pop(c, true)
                      : null,
                  child: Text(
                    appStrings.pick(
                      'DELETE PERMANENTLY',
                      'ELIMINAR DEFINITIVAMENTE',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      controller.dispose();
      return;
    }
    controller.dispose();
    await _client.rpc(
      'platform_delete_gym',
      params: {'p_gym_id': gym.id, 'p_confirmation_name': gym.name},
    );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    appBar: AppBar(
      title: Text(appStrings.pick('GYM DETAIL', 'DETALLE DEL GIMNASIO')),
    ),
    body: _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        : _error != null
        ? Center(child: Text(_error!))
        : ListView(
            padding: const EdgeInsets.all(AppSpacing.screenX),
            children: [
              OwnerGymCrmHeader(gym: _gym!),
              const SizedBox(height: AppSpacing.md),
              OwnerGymContactSection(
                detail: _detail!,
                onCall: (value) => _openContact('tel', value),
                onEmail: (value) => _openContact('mailto', value),
              ),
              const SizedBox(height: AppSpacing.md),
              OwnerGymPlanSection(gym: _gym!),
              if (_pendingPlanRequest != null) ...[
                const SizedBox(height: AppSpacing.sm),
                OwnerPlanRequestCard(
                  request: _pendingPlanRequest!,
                  onApprove: () => _reviewPending(true),
                  onReject: () => _reviewPending(false),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                key: const ValueKey('platform-change-saas-plan'),
                onPressed: _changeSaasPlan,
                child: Text(
                  appStrings.pick('CHANGE SAAS PLAN', 'CAMBIAR PLAN SAAS'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OwnerGymOperationalSection(gym: _gym!),
              const SizedBox(height: AppSpacing.md),
              OwnerGymDataSection(gym: _gym!),
              const SizedBox(height: AppSpacing.xl),
              if (_gym!.status == 'active')
                OutlinedButton.icon(
                  key: const ValueKey('owner-enter-as-admin'),
                  icon: const Icon(Icons.login_rounded),
                  label: Text(
                    appStrings.pick('ENTER AS ADMIN', 'ENTRAR COMO ADMIN'),
                  ),
                  onPressed: _enterAdmin,
                ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                appStrings.pick('ADMINISTRATION', 'ADMINISTRACIÓN'),
                style: AppTypography.sectionTitle(
                  context,
                ).copyWith(color: AppColors.danger),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_gym!.status != 'suspended')
                OutlinedButton(
                  onPressed: () => _setStatus('suspended'),
                  child: Text(
                    appStrings.pick('SUSPEND GYM', 'BLOQUEAR GIMNASIO'),
                  ),
                ),
              if (_gym!.status == 'suspended' || _gym!.status == 'archived')
                OutlinedButton(
                  onPressed: () => _setStatus('active'),
                  child: Text(
                    appStrings.pick('REACTIVATE GYM', 'REACTIVAR GIMNASIO'),
                  ),
                ),
              if (_gym!.status != 'archived')
                OutlinedButton(
                  onPressed: () => _setStatus('archived'),
                  child: Text(appStrings.pick('ARCHIVE', 'ARCHIVAR')),
                ),
              if (_gym!.status == 'archived')
                TextButton(
                  onPressed: _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  child: Text(
                    appStrings.pick(
                      'DELETE PERMANENTLY',
                      'ELIMINAR DEFINITIVAMENTE',
                    ),
                  ),
                ),
            ],
          ),
  );
}

class OwnerGymCrmHeader extends StatelessWidget {
  const OwnerGymCrmHeader({super.key, required this.gym});
  final OwnerGymSummary gym;
  @override
  Widget build(BuildContext context) {
    final percent = gym.capacityPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(gym.name, style: AppTypography.itemTitle(context)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _OwnerStatusPill(status: gym.status),
            Text(
              gym.saasPlanName,
              style: AppTypography.sectionTitle(
                context,
              ).copyWith(color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(gym.saasUsageLabel, style: AppTypography.body(context)),
        if (percent != null) Text('${percent.toStringAsFixed(0)}% capacity'),
      ],
    );
  }
}

class _OwnerSection extends StatelessWidget {
  const _OwnerSection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      border: Border.all(color: AppColors.border(context)),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.sectionTitle(context)),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    ),
  );
}

class OwnerGymContactSection extends StatelessWidget {
  const OwnerGymContactSection({
    super.key,
    required this.detail,
    required this.onCall,
    required this.onEmail,
  });
  final Map<String, dynamic> detail;
  final ValueChanged<String> onCall;
  final ValueChanged<String> onEmail;

  @override
  Widget build(BuildContext context) {
    final contact = Map<String, dynamic>.from(
      detail['contact'] as Map? ?? const {},
    );
    final admins = List<Map<String, dynamic>>.from(
      (detail['admins'] as List? ?? const []).map(
        (admin) => Map<String, dynamic>.from(admin as Map),
      ),
    );
    final gymLines = <String>[
      if ((contact['phone']?.toString().trim() ?? '').isNotEmpty)
        contact['phone'].toString(),
      if ((contact['email']?.toString().trim() ?? '').isNotEmpty)
        contact['email'].toString(),
      if ((contact['website']?.toString().trim() ?? '').isNotEmpty)
        contact['website'].toString(),
      if ((contact['address']?.toString().trim() ?? '').isNotEmpty)
        contact['address'].toString(),
    ];
    return _OwnerSection(
      title: appStrings.pick('CONTACT', 'CONTACTO'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gymLines.isNotEmpty) ...[
            Text(
              appStrings.pick('Gym contact', 'Contacto del gimnasio'),
              style: AppTypography.buttonLabel(context),
            ),
            ...gymLines.map(Text.new),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                if ((contact['phone']?.toString().trim() ?? '').isNotEmpty)
                  TextButton.icon(
                    onPressed: () => onCall(contact['phone'].toString()),
                    icon: const Icon(Icons.call_outlined),
                    label: Text(appStrings.pick('CALL', 'LLAMAR')),
                  ),
                if ((contact['email']?.toString().trim() ?? '').isNotEmpty)
                  TextButton.icon(
                    onPressed: () => onEmail(contact['email'].toString()),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('EMAIL'),
                  ),
              ],
            ),
          ],
          Text(
            appStrings.pick('ADMINS', 'ADMINISTRADORES'),
            style: AppTypography.buttonLabel(context),
          ),
          if (admins.isEmpty)
            Text(
              appStrings.pick(
                'No active administrator contact is available.',
                'No hay contacto de administrador activo disponible.',
              ),
            )
          else
            ...admins.map((admin) {
              final name = admin['full_name']?.toString().trim();
              final email = admin['email']?.toString().trim();
              final phone = admin['phone']?.toString().trim();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name?.isNotEmpty == true
                          ? name!
                          : appStrings.pick('Administrator', 'Administrador'),
                      style: AppTypography.body(context),
                    ),
                    if (email?.isNotEmpty == true) Text(email!),
                    if (phone?.isNotEmpty == true) Text(phone!),
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        if (phone?.isNotEmpty == true)
                          TextButton.icon(
                            onPressed: () => onCall(phone!),
                            icon: const Icon(Icons.call_outlined),
                            label: Text(appStrings.pick('CALL', 'LLAMAR')),
                          ),
                        if (email?.isNotEmpty == true)
                          TextButton.icon(
                            onPressed: () => onEmail(email!),
                            icon: const Icon(Icons.email_outlined),
                            label: const Text('EMAIL'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class OwnerGymPlanSection extends StatelessWidget {
  const OwnerGymPlanSection({super.key, required this.gym});
  final OwnerGymSummary gym;
  @override
  Widget build(BuildContext context) {
    final percent = gym.capacityPercent;
    return _OwnerSection(
      title: appStrings.pick('PLAN', 'PLAN'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(gym.saasPlanName, style: AppTypography.itemTitle(context)),
          Text('€${gym.saasMonthlyPrice} / ${appStrings.pick('month', 'mes')}'),
          Text(gym.saasUsageLabel),
          if (gym.saasLimit == null)
            Text(appStrings.pick('No member limit', 'Sin límite de miembros'))
          else ...[
            Text(
              '${gym.count('saas_remaining_slots')} ${appStrings.pick('slots available', 'plazas disponibles')}',
            ),
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(
              value: ((percent ?? 0) / 100).clamp(0, 1),
              color: AppColors.primary,
              backgroundColor: AppColors.surfaceAlt(context),
            ),
            Text('${(percent ?? 0).toStringAsFixed(0)}% capacity'),
          ],
        ],
      ),
    );
  }
}

class OwnerGymOperationalSection extends StatelessWidget {
  const OwnerGymOperationalSection({super.key, required this.gym});
  final OwnerGymSummary gym;
  @override
  Widget build(BuildContext context) => _OwnerSection(
    title: appStrings.pick('OPERATIONAL USAGE', 'USO OPERATIVO'),
    child: Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        Text('${gym.saasAthletes} active athletes'),
        Text('${gym.inactiveAthletes} inactive athletes'),
        Text('${gym.count('admin_count')} admins'),
        Text('${gym.count('coach_count')} coaches'),
        Text('${gym.count('active_membership_count')} active memberships'),
        Text('${gym.count('class_count')} classes'),
        Text('${gym.count('booking_count')} bookings'),
        Text('Stripe: ${gym.stripeLabel}'),
      ],
    ),
  );
}

class OwnerGymDataSection extends StatelessWidget {
  const OwnerGymDataSection({super.key, required this.gym});
  final OwnerGymSummary gym;
  @override
  Widget build(BuildContext context) => _OwnerSection(
    title: appStrings.pick('DATA & STORAGE', 'DATOS Y STORAGE'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${gym.databaseRecords} ${appStrings.pick('tenant data records', 'registros tenant')}',
        ),
        Text(
          '${gym.databaseShare.toStringAsFixed(1)}% ${appStrings.pick('of counted tenant records', 'de los registros tenant contabilizados')}',
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          appStrings.pick(
            'Storage cannot be attributed reliably by gym with the current object paths.',
            'El storage no puede atribuirse de forma fiable por gimnasio con las rutas actuales.',
          ),
          style: AppTypography.helper(context),
        ),
      ],
    ),
  );
}
