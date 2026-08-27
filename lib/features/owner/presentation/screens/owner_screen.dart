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
  int count(String key) => (data[key] as num?)?.toInt() ?? 0;
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

  Future<void> _select(OwnerGymSummary gym) async {
    await _client.rpc(
      'select_owner_effective_gym',
      params: {'p_gym_id': gym.id},
    );
    if (!mounted) return;
    context.go('/app?section=panel');
  }

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
              await _client.rpc(
                'select_owner_effective_gym',
                params: {'p_gym_id': gym.id},
              );
              await _client.functions.invoke(
                'owner-invite-admin',
                body: {
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
  Widget build(BuildContext context) => Scaffold(
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
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          else if (_error != null)
            Text(_error!, style: TextStyle(color: AppColors.danger))
          else
            ..._gyms.map(
              (gym) => _OwnerGymRow(
                gym: gym,
                onTap: () => _select(gym),
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
        '${gym.count('active_member_count')} ${appStrings.pick('active members', 'miembros activos')}\n${gym.count('admin_count')} admins · ${gym.count('coach_count')} coaches · ${gym.count('athlete_count')} ${appStrings.pick('athletes', 'atletas')}\n${gym.count('active_membership_count')} memberships · ${gym.stripeLabel}',
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
