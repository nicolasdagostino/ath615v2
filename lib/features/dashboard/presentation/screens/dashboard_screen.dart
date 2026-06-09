import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../widgets/manage_plans_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.gymName,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final String? gymName;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum _DashboardTab { overview, members, plans }

enum _MemberRoleFilter { all, athlete, coach, admin }

class _DashboardScreenState extends State<DashboardScreen> {
  final _search = TextEditingController();

  bool _loadingMembers = true;
  _DashboardTab _selectedTab = _DashboardTab.overview;
  _MemberRoleFilter _roleFilter = _MemberRoleFilter.all;
  List<Map<String, dynamic>> _members = [];
  String? _gymId;

  int get _allMembersCount => _members.length;

  int get _athletesCount =>
      _members.where((m) => m['role'] == 'athlete').length;

  int get _coachesCount => _members.where((m) => m['role'] == 'coach').length;

  int get _adminsCount => _members.where((m) => m['role'] == 'admin').length;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);

    try {
      final result = await Supabase.instance.client.functions.invoke(
        'admin-list-members',
      );

      final data = Map<String, dynamic>.from(result.data as Map);
      final members = List<Map<String, dynamic>>.from(data['members'] as List);

      final gymId = members.isEmpty
          ? _gymId
          : members.first['gym_id']?.toString();

      if (!mounted) return;
      setState(() {
        _gymId = gymId;
        _members = members;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.loadMembersError(e))));
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _inviteAthlete({
    required String email,
    String? fullName,
    String? phone,
    String? birthDate,
    String role = 'athlete',
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'admin-invite-athlete',
        body: {
          'email': email.trim(),
          'full_name': fullName?.trim(),
          'phone': phone?.trim(),
          'birth_date': birthDate?.trim(),
          'role': role,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.athleteInvitationSent)));

      await _loadMembers();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.inviteAthleteError(e))));
    }
  }

  Future<void> _resendInvitation(Map<String, dynamic> member) async {
    try {
      debugPrint('Calling resend for: ${member['id']}');
      final result = await Supabase.instance.client.functions.invoke(
        'admin-resend-athlete-invite',
        body: {'member_id': member['id']},
      );

      debugPrint('Resend result data: ${result.data}');
      debugPrint('Resend result status: ${result.status}');

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.athleteInvitationSent)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.inviteAthleteError(e))));
    }
  }

  Future<void> _deletePendingMember(Map<String, dynamic> member) async {
    final name = (member['full_name'] ?? member['email'] ?? 'this member')
        .toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete invitation?'),
        content: Text(
          'This will permanently remove $name from your members list. Only pending invitations can be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'admin-delete-pending-member',
        body: {'member_id': member['id'].toString()},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation deleted')));

      await _loadMembers();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.inviteAthleteError(e))));
    }
  }

  Future<void> _openInviteMemberSheet() async {
    final email = TextEditingController();
    final fullName = TextEditingController();
    final phone = TextEditingController();
    final birthDate = TextEditingController();

    String role = 'athlete';
    var inviting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.inviteAthlete.toUpperCase(),
                      style: _DashText.section,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appStrings.inviteAthleteDescription,
                      style: _DashText.subtle,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: fullName,
                      style: _DashText.body,
                      decoration: _dashInput(
                        appStrings.fullName,
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      style: _DashText.body,
                      decoration: _dashInput(
                        appStrings.athleteEmail,
                        Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      style: _DashText.body,
                      decoration: _dashInput(
                        appStrings.phone,
                        Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: inviting ? null : () => _pickBirthDate(birthDate),
                      child: IgnorePointer(
                        child: TextField(
                          controller: birthDate,
                          style: _DashText.body,
                          decoration: _dashInput(
                            appStrings.birthDate,
                            Icons.cake_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: _dashInput(
                        appStrings.role,
                        Icons.shield_outlined,
                      ),
                      style: _DashText.body,
                      dropdownColor: Colors.white,
                      items: [
                        DropdownMenuItem(
                          value: 'athlete',
                          child: Text(appStrings.member),
                        ),
                        DropdownMenuItem(
                          value: 'coach',
                          child: Text(appStrings.coach),
                        ),
                        const DropdownMenuItem(
                          value: 'admin',
                          child: Text('Admin'),
                        ),
                      ],
                      onChanged: inviting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setSheetState(() {
                                role = value;
                              });
                            },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: appStrings.cancel,
                            onPressed: inviting ? null : () => context.pop(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AppButton(
                            label: appStrings.inviteAthlete,
                            loading: inviting,
                            onPressed: inviting
                                ? null
                                : () async {
                                    setSheetState(() {
                                      inviting = true;
                                    });

                                    await _inviteAthlete(
                                      email: email.text,
                                      fullName: fullName.text,
                                      phone: phone.text,
                                      birthDate: birthDate.text,
                                      role: role,
                                    );

                                    if (context.mounted) {
                                      context.pop();
                                    }
                                  },
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
      },
    );
  }

  Future<void> _openPlans() async {
    final gymId = _gymId;
    if (gymId == null) return;

    await showManagePlansSheet(context: context, gymId: gymId);
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final q = _search.text.trim().toLowerCase();

    var filtered = _members.where((m) {
      final name = (m['full_name'] ?? '').toString().toLowerCase();
      final email = (m['email'] ?? '').toString().toLowerCase();

      final matchesSearch = q.isEmpty || name.contains(q) || email.contains(q);

      if (!matchesSearch) return false;

      final role = (m['role'] ?? '').toString();

      switch (_roleFilter) {
        case _MemberRoleFilter.athlete:
          return role == 'athlete';

        case _MemberRoleFilter.coach:
          return role == 'coach';

        case _MemberRoleFilter.admin:
          return role == 'admin';

        case _MemberRoleFilter.all:
          return true;
      }
    });

    return filtered.toList();
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.day}/${date.month}/${date.year}';
  }

  String _dateInputValue(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _pickBirthDate(TextEditingController controller) async {
    final current = DateTime.tryParse(controller.text);
    final now = DateTime.now();

    final picked = await showAppDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked == null) return;
    controller.text = _dateInputValue(picked);
  }

  Future<void> _openEditMemberSheet(Map<String, dynamic> member) async {
    final gymId = _gymId;
    final memberId = member['id']?.toString();
    final memberGymId = member['gym_id']?.toString();
    if (gymId == null || memberId == null || memberGymId != gymId) return;

    final fullName = TextEditingController(
      text: member['full_name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: member['phone']?.toString() ?? '',
    );
    final birthDate = TextEditingController(
      text: member['birth_date']?.toString() ?? '',
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
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
                  Text(
                    appStrings.editMember.toUpperCase(),
                    style: _DashText.section,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: fullName,
                    textCapitalization: TextCapitalization.words,
                    style: _DashText.body,
                    decoration: _dashInput(
                      appStrings.fullName,
                      Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    style: _DashText.body,
                    decoration: _dashInput(
                      appStrings.phone,
                      Icons.phone_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: birthDate,
                    readOnly: true,
                    style: _DashText.body,
                    decoration: _dashInput(
                      appStrings.birthDate,
                      Icons.calendar_month_rounded,
                    ),
                    onTap: () => _pickBirthDate(birthDate),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: appStrings.saveChanges,
                    onPressed: () async {
                      try {
                        final updated = await Supabase.instance.client
                            .rpc(
                              'update_gym_member_profile',
                              params: {
                                'p_member_id': memberId,
                                'p_full_name': fullName.text.trim(),
                                'p_phone': phone.text.trim(),
                                'p_birth_date': birthDate.text.trim().isEmpty
                                    ? null
                                    : birthDate.text.trim(),
                              },
                            )
                            .single();

                        member
                          ..['full_name'] = updated['full_name']
                          ..['phone'] = updated['phone']
                          ..['birth_date'] = updated['birth_date'];

                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.pop(sheetContext);

                        setState(() {
                          final index = _members.indexWhere(
                            (m) => m['id']?.toString() == memberId,
                          );
                          if (index != -1) {
                            _members[index] = {
                              ..._members[index],
                              ...Map<String, dynamic>.from(updated),
                            };
                          }
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(appStrings.memberUpdated)),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(appStrings.updateMemberError(e)),
                          ),
                        );
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
  }

  String _creditReasonLabel(String reason) {
    if (reason == 'assigned') return appStrings.assigned;
    if (reason == 'booked') return appStrings.booked;
    if (reason == 'cancelled') return appStrings.cancelled;
    return reason;
  }

  Future<Map<String, dynamic>> _loadMemberMembershipData(
    String memberId,
  ) async {
    final membership = await Supabase.instance.client
        .from('member_memberships')
        .select(
          'id, credits_remaining, expires_at, membership_plans(name, plan_type)',
        )
        .eq('user_id', memberId)
        .eq('is_active', true)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .maybeSingle();

    final logs = await Supabase.instance.client
        .from('membership_credit_logs')
        .select('amount, reason, created_at')
        .eq('user_id', memberId)
        .order('created_at', ascending: false)
        .limit(12);

    return {
      'membership': membership,
      'logs': List<Map<String, dynamic>>.from(logs),
    };
  }

  Future<Map<String, dynamic>> _loadMemberStats(String memberId) async {
    final attended = await Supabase.instance.client
        .from('class_bookings')
        .select('id')
        .eq('user_id', memberId)
        .eq('status', 'attended');

    return {'attended_count': List<Map<String, dynamic>>.from(attended).length};
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

  Future<void> _toggleMemberActive(Map<String, dynamic> member) async {
    final memberId = member['id']?.toString();

    if (memberId == null) return;

    final current = member['is_active'] == true;
    final next = !current;

    try {
      final updated = await Supabase.instance.client
          .rpc(
            'set_gym_member_active',
            params: {'p_member_id': memberId, 'p_is_active': next},
          )
          .single();

      if (!mounted) return;

      setState(() {
        final index = _members.indexWhere(
          (m) => m['id']?.toString() == memberId,
        );

        if (index != -1) {
          _members[index] = {
            ..._members[index],
            'is_active': updated['is_active'] == true,
          };
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Member activated successfully.'
                : 'Member deactivated successfully.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update member status: $e')),
      );
    }
  }

  Future<void> _openAssignPlan(String userId) async {
    final rootContext = context;
    final gymId = _gymId;
    if (gymId == null) return;

    final client = Supabase.instance.client;

    final plans = await client
        .from('membership_plans')
        .select('id, name, plan_type, credits')
        .eq('gym_id', gymId)
        .eq('is_active', true);

    String? selectedPlanId;
    var saving = false;

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                        appStrings.assignPlan.toUpperCase(),
                        style: _DashText.title,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPlanId,
                        decoration: _dashInput(
                          appStrings.selectPlan,
                          Icons.card_membership_outlined,
                        ),
                        items: List<Map<String, dynamic>>.from(plans).map((
                          plan,
                        ) {
                          final name =
                              plan['name']?.toString() ?? appStrings.plan;
                          final credits = plan['credits'];

                          final label = credits == null
                              ? '$name · ${appStrings.unlimited}'
                              : '$name · $credits ${appStrings.creditsLower}';

                          return DropdownMenuItem<String>(
                            value: plan['id'].toString(),
                            child: Text(label, style: _DashText.body),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                setSheetState(() {
                                  selectedPlanId = value;
                                });
                              },
                      ),
                      const SizedBox(height: 18),
                      AppButton(
                        label: appStrings.assign,
                        loading: saving,
                        onPressed: selectedPlanId == null || saving
                            ? null
                            : () async {
                                setSheetState(() {
                                  saving = true;
                                });

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

                                  if (!rootContext.mounted) return;
                                } catch (e) {
                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(
                                    rootContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        appStrings.assignPlanError(e),
                                      ),
                                    ),
                                  );
                                } finally {
                                  if (context.mounted) {
                                    setSheetState(() {
                                      saving = false;
                                    });
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

  void _openMember(Map<String, dynamic> member) {
    String historyFilter = 'all';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final email = (member['email'] ?? '-').toString();
            final name = (member['full_name'] ?? email).toString();
            String selectedRole = (member['role'] ?? 'athlete').toString();
            final phone = member['phone']?.toString();
            final active = member['is_active'] == true;
            final birthDate =
                member['birth_date']?.toString() ?? appStrings.notSet;
            return FutureBuilder<List<dynamic>>(
              future: Future.wait([
                _loadMemberHistory(member['id']),
                _loadMemberMembershipData(member['id']),
                _loadMemberStats(member['id']),
              ]),
              builder: (context, snapshot) {
                final history = snapshot.hasData
                    ? List<Map<String, dynamic>>.from(snapshot.data![0] as List)
                    : <Map<String, dynamic>>[];

                final filteredHistory = historyFilter == 'all'
                    ? history
                    : history
                          .where(
                            (h) => h['status']?.toString() == historyFilter,
                          )
                          .toList();

                final membershipData = snapshot.hasData
                    ? snapshot.data![1] as Map<String, dynamic>
                    : <String, dynamic>{};

                final membership =
                    membershipData['membership'] as Map<String, dynamic>?;

                final creditLogs = List<Map<String, dynamic>>.from(
                  membershipData['logs'] ?? [],
                );

                final stats = snapshot.hasData
                    ? snapshot.data![2] as Map<String, dynamic>
                    : <String, dynamic>{};
                final attendedCount = stats['attended_count'] as int? ?? 0;

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: SafeArea(
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.86,
                      ),
                      margin: const EdgeInsets.fromLTRB(16, 72, 16, 16),
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: ListView(
                        shrinkWrap: false,
                        children: [
                          Center(
                            child: Container(
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD7DAE0),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF262626),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  name.trim().isEmpty
                                      ? 'A'
                                      : name.trim()[0].toUpperCase(),
                                  style: GoogleFonts.barlowCondensed(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFB59B6A),
                                    height: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _DashText.title,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _DashText.subtle,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appStrings.role.toUpperCase(),
                                style: _DashText.subtle,
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: selectedRole,
                                decoration: _dashInput(
                                  appStrings.role,
                                  Icons.admin_panel_settings_outlined,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'athlete',
                                    child: Text(appStrings.member),
                                  ),
                                  DropdownMenuItem(
                                    value: 'admin',
                                    child: Text('Admin'),
                                  ),
                                ],
                                onChanged: (value) async {
                                  if (value == null || value == selectedRole) {
                                    return;
                                  }

                                  try {
                                    await Supabase.instance.client.rpc(
                                      'update_member_role',
                                      params: {
                                        'p_member_id': member['id'],
                                        'p_role': value,
                                      },
                                    );

                                    member['role'] = value;

                                    final currentUser = Supabase
                                        .instance
                                        .client
                                        .auth
                                        .currentUser;
                                    final currentUserId = currentUser?.id;
                                    final currentUserEmail = currentUser?.email
                                        ?.trim()
                                        .toLowerCase();
                                    final memberId = member['id']?.toString();
                                    final memberEmail = member['email']
                                        ?.toString()
                                        .trim()
                                        .toLowerCase();

                                    final changedOwnRole =
                                        (currentUserId != null &&
                                            memberId == currentUserId) ||
                                        (currentUserEmail != null &&
                                            memberEmail == currentUserEmail);

                                    if (changedOwnRole && value != 'admin') {
                                      await Supabase.instance.client.auth
                                          .signOut();

                                      if (!context.mounted) return;
                                      context.go('/login');
                                      return;
                                    }

                                    if (!context.mounted) return;

                                    setSheetState(() {
                                      selectedRole = value;
                                    });

                                    setState(() {
                                      final index = _members.indexWhere(
                                        (m) => m['id'] == member['id'],
                                      );

                                      if (index != -1) {
                                        _members[index] = {
                                          ..._members[index],
                                          'role': value,
                                        };
                                      }
                                    });

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Role updated'),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error updating role: $e',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          _MemberDetailInfoRow(
                            label: appStrings.status,
                            value: active
                                ? appStrings.active
                                : appStrings.inactive,
                          ),
                          _MemberDetailInfoRow(
                            label: appStrings.birthDate,
                            value: birthDate,
                          ),
                          _MemberDetailInfoRow(
                            label: appStrings.phone,
                            value: (phone == null || phone.trim().isEmpty)
                                ? appStrings.notSet
                                : phone,
                          ),
                          const SizedBox(height: 12),
                          AppButton(
                            label: appStrings.editMember,
                            onPressed: () async {
                              await _openEditMemberSheet(member);
                              if (!context.mounted) return;
                              setSheetState(() {});
                            },
                          ),
                          const SizedBox(height: 18),
                          _MemberMilestoneCard(attendedCount: attendedCount),
                          const SizedBox(height: 18),
                          _MemberDetailCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appStrings.membershipTitle.toUpperCase(),
                                  style: _DashText.section,
                                ),
                                const SizedBox(height: 12),
                                if (membership == null)
                                  Text(
                                    appStrings.noActivePlan,
                                    style: _DashText.subtle,
                                  )
                                else ...[
                                  _MemberDetailInfoRow(
                                    label: appStrings.activePlan,
                                    value:
                                        '${(membership['membership_plans'] as Map?)?['name'] ?? appStrings.plan}',
                                  ),
                                  _MemberDetailInfoRow(
                                    label: appStrings.credits,
                                    value:
                                        '${membership['credits_remaining'] ?? appStrings.unlimited}',
                                  ),
                                  _MemberDetailInfoRow(
                                    label: appStrings.expires,
                                    value: _formatDate(
                                      membership['expires_at']?.toString(),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Text(
                                  appStrings.creditHistory.toUpperCase(),
                                  style: _DashText.section,
                                ),
                                const SizedBox(height: 10),
                                if (creditLogs.isEmpty)
                                  Text(
                                    appStrings.noCreditHistory,
                                    style: _DashText.subtle,
                                  )
                                else
                                  ...creditLogs.map((log) {
                                    final amount = log['amount'];
                                    final sign = (amount is int && amount > 0)
                                        ? '+'
                                        : '';

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        '$sign$amount · ${_creditReasonLabel(log['reason']?.toString() ?? '')} · ${_formatDate(log['created_at']?.toString())}',
                                        style: _DashText.subtle,
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          AppButton(
                            label: appStrings.assignPlan,
                            onPressed: () => _openAssignPlan(member['id']),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            appStrings.recentClasses.toUpperCase(),
                            style: _DashText.section,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _MemberFilterChip(
                                  label:
                                      '${appStrings.all} ($_allMembersCount)',
                                  selected: historyFilter == 'all',
                                  onTap: () => setSheetState(
                                    () => historyFilter = 'all',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MemberFilterChip(
                                  label: appStrings.attended.toUpperCase(),
                                  selected: historyFilter == 'attended',
                                  onTap: () => setSheetState(
                                    () => historyFilter = 'attended',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MemberFilterChip(
                                  label: appStrings.noShow.toUpperCase(),
                                  selected: historyFilter == 'no_show',
                                  onTap: () => setSheetState(
                                    () => historyFilter = 'no_show',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!snapshot.hasData)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFB59B6A),
                                ),
                              ),
                            )
                          else if (filteredHistory.isEmpty)
                            Text(appStrings.noClasses, style: _DashText.subtle)
                          else
                            ...filteredHistory.map((h) {
                              final klass = h['classes'];
                              final title =
                                  klass?['title']?.toString() ??
                                  appStrings.classFallback;
                              final startsAt =
                                  klass?['starts_at']?.toString() ?? '';
                              final status = h['status']?.toString() ?? '';

                              return _MemberHistoryRow(
                                title: title,
                                subtitle: startsAt,
                                status: status,
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
      backgroundColor: const Color(0xFF171717),
      body: Column(
        children: [
          _DashboardHeader(
            gymName: widget.gymName,
            unreadNotifications: widget.unreadNotifications,
            onManagePlans: _openPlans,
            onOpenNotifications: widget.onOpenNotifications,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.dashboardTitle,
                    selected: _selectedTab == _DashboardTab.overview,
                    onTap: () {
                      setState(() {
                        _selectedTab = _DashboardTab.overview;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.members,
                    selected: _selectedTab == _DashboardTab.members,
                    onTap: () {
                      setState(() {
                        _selectedTab = _DashboardTab.members;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.membershipTitle,
                    selected: _selectedTab == _DashboardTab.plans,
                    onTap: () {
                      setState(() {
                        _selectedTab = _DashboardTab.plans;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFFB59B6A),
              onRefresh: _loadMembers,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                children: [
                  if (_selectedTab == _DashboardTab.overview) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: appStrings.members,
                            value: '${_members.length}',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _MetricCard(
                            label: appStrings.active,
                            value:
                                '${_members.where((m) => m['is_active'] == true).length}',
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (_selectedTab == _DashboardTab.members) ...[
                    _DashboardCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      appStrings.members.toUpperCase(),
                                      style: _DashText.section,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      appStrings.dashboardHeaderSubtitle,
                                      style: _DashText.subtle,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 160,
                                child: AppButton(
                                  label: appStrings.inviteAthlete,
                                  onPressed: _openInviteMemberSheet,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: _DashText.body,
                            decoration: _dashInput(
                              appStrings.searchMember,
                              Icons.search,
                            ),
                          ),
                          const SizedBox(height: 16),

                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _RoleFilterChip(
                                  label: appStrings.all,
                                  selected:
                                      _roleFilter == _MemberRoleFilter.all,
                                  onTap: () {
                                    setState(() {
                                      _roleFilter = _MemberRoleFilter.all;
                                    });
                                  },
                                ),
                                const SizedBox(width: 10),
                                _RoleFilterChip(
                                  label: 'Athletes ($_athletesCount)',
                                  selected:
                                      _roleFilter == _MemberRoleFilter.athlete,
                                  onTap: () {
                                    setState(() {
                                      _roleFilter = _MemberRoleFilter.athlete;
                                    });
                                  },
                                ),
                                const SizedBox(width: 10),
                                _RoleFilterChip(
                                  label: 'Coaches ($_coachesCount)',
                                  selected:
                                      _roleFilter == _MemberRoleFilter.coach,
                                  onTap: () {
                                    setState(() {
                                      _roleFilter = _MemberRoleFilter.coach;
                                    });
                                  },
                                ),
                                const SizedBox(width: 10),
                                _RoleFilterChip(
                                  label: 'Admins ($_adminsCount)',
                                  selected:
                                      _roleFilter == _MemberRoleFilter.admin,
                                  onTap: () {
                                    setState(() {
                                      _roleFilter = _MemberRoleFilter.admin;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          if (_loadingMembers)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 22),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFB59B6A),
                                ),
                              ),
                            )
                          else if (members.isEmpty)
                            Text(
                              appStrings.noMembersFound,
                              style: _DashText.subtle,
                            )
                          else
                            ...members.map(
                              (member) => _MemberTile(
                                member: member,
                                onTap: () => _openMember(member),
                                onAssignPlan: () =>
                                    _openAssignPlan(member['id'].toString()),
                                onToggleActive: () =>
                                    _toggleMemberActive(member),
                                onResendInvitation: () =>
                                    _resendInvitation(member),
                                onDeletePendingMember: () =>
                                    _deletePendingMember(member),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedTab == _DashboardTab.plans) ...[
                    _DashboardCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appStrings.managePlans.toUpperCase(),
                            style: _DashText.section,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            appStrings.manageMembershipsDescription,
                            style: _DashText.subtle,
                          ),
                          const SizedBox(height: 18),
                          AppButton(
                            label: appStrings.managePlans,
                            onPressed: _openPlans,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.onTap,
    required this.onAssignPlan,
    required this.onToggleActive,
    required this.onResendInvitation,
    required this.onDeletePendingMember,
  });

  final Map<String, dynamic> member;
  final VoidCallback onTap;
  final Future<void> Function() onAssignPlan;
  final Future<void> Function() onToggleActive;
  final Future<void> Function() onResendInvitation;
  final Future<void> Function() onDeletePendingMember;

  @override
  Widget build(BuildContext context) {
    final email = (member['email'] ?? '-').toString();
    final name = (member['full_name'] ?? email).toString();
    final role = (member['role'] ?? '-').toString();
    final active = member['is_active'] == true;
    final status =
        (member['invitation_status'] ?? (active ? 'active' : 'disabled'))
            .toString();
    final isPending = status == 'pending';
    final isDisabled = status == 'disabled';
    final statusLabel = isPending
        ? 'Pending'
        : isDisabled
        ? 'Disabled'
        : 'Active';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Opacity(
            opacity: active ? 1 : 0.55,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  _MemberAvatar(
                    name: name,
                    avatarUrl: member['avatar_url']?.toString(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _DashText.title,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$email · $statusLabel · $role',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _DashText.subtle,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: Color(0xFF8F96A3),
                    ),
                    onSelected: (value) async {
                      if (value == 'plan') {
                        await onAssignPlan();
                      }

                      if (value == 'toggle_active') {
                        await onToggleActive();
                      }

                      if (value == 'resend') {
                        debugPrint('RESEND CLICKED');
                        await onResendInvitation();
                      }

                      if (value == 'delete_pending') {
                        await onDeletePendingMember();
                      }
                    },
                    itemBuilder: (context) => [
                      if (!isDisabled)
                        PopupMenuItem(
                          value: 'plan',
                          child: Text(appStrings.assignPlan),
                        ),
                      PopupMenuItem(
                        value: 'toggle_active',
                        child: Text(
                          active
                              ? appStrings.deactivateMember
                              : appStrings.activateMember,
                        ),
                      ),
                      if (isPending)
                        PopupMenuItem(
                          value: 'resend',
                          child: Text(appStrings.resendInvitation),
                        ),
                      if (isPending)
                        const PopupMenuItem(
                          value: 'delete_pending',
                          child: Text('Delete invitation'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        color: const Color(0xFFF7F3EA),
        child: hasAvatar
            ? Image.network(
                avatarUrl!,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
              )
            : Text(
                name.trim().isEmpty ? 'A' : name.trim()[0].toUpperCase(),
                style: GoogleFonts.barlowCondensed(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB59B6A),
                  height: 1,
                ),
              ),
      ),
    );
  }
}

InputDecoration _dashInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlowCondensed(
      color: const Color(0xFF8F96A3),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
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

class _DashText {
  const _DashText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle section = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: 0.8,
    height: 1.0,
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
    height: 1.0,
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.gymName,
    required this.unreadNotifications,
    required this.onManagePlans,
    required this.onOpenNotifications,
  });

  final String? gymName;
  final int unreadNotifications;
  final VoidCallback onManagePlans;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF171717),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 132,
                    child: Text(
                      gymName ?? appStrings.appBrand,
                      style: _DashText.title.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.dashboardTitle.toUpperCase(),
                      style: _DashText.title.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appStrings.dashboardHeaderSubtitle,
                      style: _DashText.subtle.copyWith(
                        color: const Color(0xFFB8BDC7),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: 132,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _HeaderIcon(
                        icon: Icons.notifications_outlined,
                        onTap: onOpenNotifications,
                        badgeCount: unreadNotifications,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3EA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Badge(
          isLabelVisible: badgeCount > 0,
          label: Text(badgeCount > 99 ? '99+' : badgeCount.toString()),
          child: Icon(icon, size: 18, color: const Color(0xFFB59B6A)),
        ),
      ),
    );
  }
}

class _RoleFilterChip extends StatelessWidget {
  const _RoleFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: Text(
        label.toUpperCase(),
        style: GoogleFonts.barlowCondensed(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: selected ? Colors.white : const Color(0xFF8F96A3),
          height: 1.0,
        ),
      ),
      selectedColor: const Color(0xFFB59B6A),
      backgroundColor: Colors.white,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => onTap(),
    );
  }
}

class _DashboardTabChip extends StatelessWidget {
  const _DashboardTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: SizedBox(
        width: double.infinity,
        child: Center(
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.barlowCondensed(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: selected ? Colors.white : const Color(0xFF8F96A3),
              height: 1.0,
            ),
          ),
        ),
      ),
      selectedColor: const Color(0xFFB59B6A),
      backgroundColor: Colors.white,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => onTap(),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _DashText.subtle),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.barlowCondensed(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0E0E11),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberMilestoneCard extends StatelessWidget {
  const _MemberMilestoneCard({required this.attendedCount});

  final int attendedCount;

  int get _target {
    for (final target in [50, 100, 200, 500]) {
      if (attendedCount < target) return target;
    }
    return 500;
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final progress = target == 0
        ? 0.0
        : (attendedCount / target).clamp(0.0, 1.0);
    final remaining = (target - attendedCount).clamp(0, target);

    return _MemberDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(appStrings.milestone.toUpperCase(), style: _DashText.section),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$attendedCount / $target ${appStrings.classesAttended}',
                  style: _DashText.title,
                ),
              ),
              Text(
                '$remaining ${appStrings.classesToGo}',
                style: _DashText.subtle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: const Color(0xFFE8EAF0),
              color: const Color(0xFFB59B6A),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberDetailCard extends StatelessWidget {
  const _MemberDetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}

class _MemberDetailInfoRow extends StatelessWidget {
  const _MemberDetailInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: _DashText.subtle)),
          const SizedBox(width: 12),
          Text(value, style: _DashText.body),
        ],
      ),
    );
  }
}

class _MemberFilterChip extends StatelessWidget {
  const _MemberFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF0E0E11) : const Color(0xFFF4F5F7),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : const Color(0xFF384152),
                letterSpacing: 0.5,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberHistoryRow extends StatelessWidget {
  const _MemberHistoryRow({
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String title;
  final String subtitle;
  final String status;

  @override
  Widget build(BuildContext context) {
    final marker = status == 'attended'
        ? '✓'
        : status == 'no_show'
        ? '✗'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _DashText.title),
                  const SizedBox(height: 4),
                  Text(subtitle, style: _DashText.subtle),
                ],
              ),
            ),
            if (marker.isNotEmpty) Text(marker, style: _DashText.title),
          ],
        ),
      ),
    );
  }
}
