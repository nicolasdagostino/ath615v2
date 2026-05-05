import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_button.dart';
import '../widgets/manage_plans_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _inviteEmail = TextEditingController();
  final _search = TextEditingController();

  bool _loading = false;
  bool _loadingMembers = true;
  List<Map<String, dynamic>> _members = [];
  String? _gymId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final myProfile = await Supabase.instance.client
          .from('profiles')
          .select('gym_id')
          .eq('id', user.id)
          .single();

      final gymId = myProfile['gym_id']?.toString();

      if (gymId == null) {
        if (!mounted) return;
        setState(() {
          _gymId = null;
          _members = [];
        });
        return;
      }

      final data = await Supabase.instance.client
          .from('profiles')
          .select(
            'id, full_name, email, role, gym_id, birth_date, is_active, created_at',
          )
          .eq('gym_id', gymId)
          .neq('role', 'owner')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _gymId = gymId;
        _members = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load members error: $e')));
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _inviteAthlete() async {
    setState(() => _loading = true);

    try {
      await Supabase.instance.client.functions.invoke(
        'admin-invite-athlete',
        body: {'email': _inviteEmail.text.trim()},
      );

      if (!mounted) return;

      _inviteEmail.clear();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Athlete invitation sent')));

      await _loadMembers();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite athlete error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPlans() async {
    final gymId = _gymId;
    if (gymId == null) return;

    await showManagePlansSheet(context: context, gymId: gymId);
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _members;

    return _members.where((m) {
      final name = (m['full_name'] ?? '').toString().toLowerCase();
      final email = (m['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadMemberHistory(String memberId) async {
    final res = await Supabase.instance.client
        .from('class_bookings')
        .select('status, created_at, classes(title, starts_at)')
        .eq('user_id', memberId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: false)
        .limit(10);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> _openAssignPlan(String userId) async {
    final gymId = _gymId;
    if (gymId == null) return;

    final client = Supabase.instance.client;

    final plans = await client
        .from('membership_plans')
        .select('id, name, plan_type, credits')
        .eq('gym_id', gymId)
        .eq('is_active', true);

    String? selectedPlanId;

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Assign plan',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPlanId,
                    hint: const Text('Select plan'),
                    items: List<Map<String, dynamic>>.from(plans).map((plan) {
                      final name = plan['name']?.toString() ?? 'Plan';
                      final credits = plan['credits'];
                      final label = credits == null
                          ? '$name · unlimited'
                          : '$name · $credits credits';

                      return DropdownMenuItem<String>(
                        value: plan['id'].toString(),
                        child: Text(label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setSheetState(() => selectedPlanId = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Assign',
                    onPressed: selectedPlanId == null
                        ? null
                        : () async {
                            try {
                              await client.rpc(
                                'assign_membership_plan',
                                params: {
                                  'p_user_id': userId,
                                  'p_plan_id': selectedPlanId,
                                },
                              );

                              if (!context.mounted) return;
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Plan assigned')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Assign plan error: $e'),
                                ),
                              );
                            }
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openMember(Map<String, dynamic> member) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        final email = (member['email'] ?? '-').toString();
        final name = (member['full_name'] ?? email).toString();
        final role = (member['role'] ?? '-').toString();
        final active = member['is_active'] == true;
        final birthDate = member['birth_date']?.toString() ?? 'Not set';

        return FutureBuilder(
          future: _loadMemberHistory(member['id']),
          builder: (context, snapshot) {
            final history = snapshot.data ?? [];

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(email),
                    const SizedBox(height: 24),
                    _DetailRow(label: 'Role', value: role),
                    _DetailRow(
                      label: 'Status',
                      value: active ? appStrings.active : appStrings.inactive,
                    ),
                    _DetailRow(label: 'Birth date', value: birthDate),

                    const SizedBox(height: 16),

                    AppButton(
                      label: 'Assign plan',
                      onPressed: () => _openAssignPlan(member['id']),
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'Recent classes',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    if (!snapshot.hasData)
                      const CircularProgressIndicator()
                    else if (history.isEmpty)
                      const Text('No classes')
                    else
                      ...history.map((h) {
                        final klass = h['classes'];
                        final status = h['status'];

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(klass['title'] ?? 'Class'),
                          subtitle: Text(klass['starts_at'] ?? ''),
                          trailing: Text(
                            status == 'attended'
                                ? '✓'
                                : status == 'no_show'
                                ? '✗'
                                : '',
                          ),
                        );
                      }),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = _filteredMembers;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  appStrings.dashboardTitle,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  tooltip: appStrings.managePlans,
                  onPressed: _openPlans,
                  icon: const Icon(Icons.card_membership),
                ),
                IconButton(
                  onPressed: _loadMembers,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  appStrings.inviteAthlete,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(appStrings.inviteAthleteDescription),
                const SizedBox(height: 20),
                TextField(
                  controller: _inviteEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: appStrings.athleteEmail,
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(
                  label: appStrings.inviteAthlete,
                  loading: _loading,
                  onPressed: _inviteAthlete,
                ),
                const SizedBox(height: 34),
                Text(
                  appStrings.members,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: appStrings.searchMember,
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loadingMembers)
                  const Center(child: CircularProgressIndicator())
                else if (members.isEmpty)
                  Text(appStrings.noMembersFound)
                else
                  ...members.map(
                    (member) => _MemberTile(
                      member: member,
                      onTap: () => _openMember(member),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onTap});

  final Map<String, dynamic> member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final email = (member['email'] ?? '-').toString();
    final name = (member['full_name'] ?? email).toString();
    final role = (member['role'] ?? '-').toString();
    final active = member['is_active'] == true;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '$email\n${active ? appStrings.active : appStrings.inactive} · $role',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
