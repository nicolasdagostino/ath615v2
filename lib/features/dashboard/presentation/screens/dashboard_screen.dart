import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';
import '../widgets/manage_plans_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

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
            'id, full_name, email, role, gym_id, phone, birth_date, is_active, created_at',
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
      ).showSnackBar(SnackBar(content: Text(appStrings.loadMembersError(e))));
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
      ).showSnackBar(SnackBar(content: Text(appStrings.athleteInvitationSent)));

      await _loadMembers();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.inviteAthleteError(e))));
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

    final picked = await showDatePicker(
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
                        onChanged: (value) {
                          setSheetState(() => selectedPlanId = value);
                        },
                      ),
                      const SizedBox(height: 18),
                      AppButton(
                        label: appStrings.assign,
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
                                    SnackBar(
                                      content: Text(appStrings.planAssigned),
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        appStrings.assignPlanError(e),
                                      ),
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
        final email = (member['email'] ?? '-').toString();
        final name = (member['full_name'] ?? email).toString();
        final role = (member['role'] ?? '-').toString();
        final phone = member['phone']?.toString();
        final active = member['is_active'] == true;
        final birthDate = member['birth_date']?.toString() ?? appStrings.notSet;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<dynamic>>(
              future: Future.wait([
                _loadMemberHistory(member['id']),
                _loadMemberMembershipData(member['id']),
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
                                  color: const Color(0xFFF7F3EA),
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
                          _MemberDetailInfoRow(
                            label: appStrings.role,
                            value: role,
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
                            onPressed: () => _openEditMemberSheet(member),
                          ),
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
                                  label: appStrings.all,
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
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Column(
          children: [
            _DashboardHeader(
              unreadNotifications: widget.unreadNotifications,
              onManagePlans: _openPlans,
              onOpenNotifications: widget.onOpenNotifications,
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFB59B6A),
                onRefresh: _loadMembers,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  children: [
                    _DashboardCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          const SizedBox(height: 16),
                          TextField(
                            controller: _inviteEmail,
                            keyboardType: TextInputType.emailAddress,
                            style: _DashText.body,
                            decoration: _dashInput(
                              appStrings.athleteEmail,
                              Icons.email_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          AppButton(
                            label: appStrings.inviteAthlete,
                            loading: _loading,
                            onPressed: _inviteAthlete,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
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
                    const SizedBox(height: 18),
                    _DashboardCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appStrings.members.toUpperCase(),
                            style: _DashText.section,
                          ),
                          const SizedBox(height: 14),
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
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F3EA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    name.trim().isEmpty ? 'A' : name.trim()[0].toUpperCase(),
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFB59B6A),
                      height: 1,
                    ),
                  ),
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
                        '$email · ${active ? appStrings.active : appStrings.inactive} · $role',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _DashText.subtle,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8F96A3),
                ),
              ],
            ),
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
    required this.unreadNotifications,
    required this.onManagePlans,
    required this.onOpenNotifications,
  });

  final int unreadNotifications;
  final VoidCallback onManagePlans;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
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
                    child: Text(appStrings.appBrand, style: _DashText.title),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.dashboardTitle.toUpperCase(),
                      style: _DashText.title,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appStrings.dashboardHeaderSubtitle,
                      style: _DashText.subtle,
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
                        icon: Icons.card_membership_outlined,
                        onTap: onManagePlans,
                      ),
                      const SizedBox(width: 8),
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
        borderRadius: BorderRadius.circular(16),
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
