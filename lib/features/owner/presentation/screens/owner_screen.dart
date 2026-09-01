import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  int? get saasLimit => (data['saas_active_member_limit'] as num?)?.toInt();
  int get saasAthletes => count('saas_active_athlete_count');
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
      final rows = await _client.rpc('list_owner_gym_overview');
      if (!mounted) return;
      setState(() {
        _gyms = List<Map<String, dynamic>>.from(
          rows as List,
        ).map(OwnerGymSummary.new).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
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
        title: Text(appStrings.pick('MY GYMS', 'MIS GIMNASIOS')),
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
            Text(
              appStrings.pick(
                '${_gyms.length} gyms',
                '${_gyms.length} gimnasios',
              ),
              key: const ValueKey('owner-gym-count'),
              style: AppTypography.sectionTitle(context),
            ),
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
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: AppColors.danger))
            else
              ...visible.map(
                (gym) => _OwnerGymRow(
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

String _ownerStatusLabel(String status) => switch (status) {
  'active' => appStrings.pick('Active', 'Activo'),
  'suspended' => appStrings.pick('Suspended', 'Suspendido'),
  'archived' => appStrings.pick('Archived', 'Archivado'),
  _ => appStrings.pick('All', 'Todos'),
};

class _OwnerGymRow extends StatelessWidget {
  const _OwnerGymRow({
    required this.gym,
    required this.onTap,
    required this.onInvite,
  });
  final OwnerGymSummary gym;
  final VoidCallback onTap, onInvite;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      border: Border.all(color: AppColors.border(context)),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      onTap: onTap,
      title: Text(
        gym.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.itemTitle(context),
      ),
      subtitle: Text(
        '${_ownerStatusLabel(gym.status).toUpperCase()} · ${gym.saasPlanName}\n${gym.saasUsageLabel}\n${gym.count('admin_count')} admins · ${gym.count('coach_count')} coaches · ${gym.stripeLabel}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: appStrings.pick(
          'Invite administrator',
          'Invitar administrador',
        ),
        icon: const Icon(Icons.person_add_alt_1, color: AppColors.primary),
        onPressed: onInvite,
      ),
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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await _client.rpc(
        'get_platform_gym_detail',
        params: {'p_gym_id': widget.gymId},
      );
      if (mounted) {
        setState(() {
          _gym = OwnerGymSummary(Map<String, dynamic>.from(row as Map));
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
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
              Text(_gym!.name, style: AppTypography.itemTitle(context)),
              const SizedBox(height: AppSpacing.sm),
              Chip(label: Text(_ownerStatusLabel(_gym!.status).toUpperCase())),
              const SizedBox(height: AppSpacing.lg),
              _OwnerSummaryBlock(gym: _gym!),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                key: const ValueKey('platform-change-saas-plan'),
                onPressed: _changeSaasPlan,
                child: Text(
                  appStrings.pick('CHANGE SAAS PLAN', 'CAMBIAR PLAN SAAS'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_gym!.status == 'active')
                AppButton(
                  label: appStrings.pick('ENTER AS ADMIN', 'ENTRAR COMO ADMIN'),
                  onPressed: _enterAdmin,
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

class _OwnerSummaryBlock extends StatelessWidget {
  const _OwnerSummaryBlock({required this.gym});
  final OwnerGymSummary gym;
  @override
  Widget build(BuildContext context) {
    final created = gym.createdAt;
    final activity = gym.lastActivityAt;
    final dates = <String>[
      if (created != null)
        appStrings.pick(
          'Created ${MaterialLocalizations.of(context).formatCompactDate(created.toLocal())}',
          'Creado ${MaterialLocalizations.of(context).formatCompactDate(created.toLocal())}',
        ),
      if (activity != null)
        appStrings.pick(
          'Last activity ${MaterialLocalizations.of(context).formatCompactDate(activity.toLocal())}',
          'Última actividad ${MaterialLocalizations.of(context).formatCompactDate(activity.toLocal())}',
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Text(
        '${gym.saasPlanName}\n${gym.saasUsageLabel}\n${gym.count('active_member_count')} ${appStrings.pick('active members', 'miembros activos')}\n${gym.count('admin_count')} admins · ${gym.count('coach_count')} coaches\n${gym.count('active_membership_count')} memberships\nStripe: ${gym.stripeLabel}${dates.isEmpty ? '' : '\n${dates.join(' · ')}'}',
        style: AppTypography.body(context),
      ),
    );
  }
}
