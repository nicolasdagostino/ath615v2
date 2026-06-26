import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../widgets/manage_plans_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';

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
  List<Map<String, dynamic>> _membershipRequests = [];
  String? _gymId;
  int _todayBookings = 0;
  int _todayClasses = 0;
  List<int> _weeklyBookings = List<int>.filled(7, 0);
  List<Map<String, dynamic>> _recentActivity = [];

  int get _athletesCount =>
      _members.where((m) => m['role'] == 'athlete').length;

  int get _coachesCount => _members.where((m) => m['role'] == 'coach').length;

  int get _adminsCount => _members.where((m) => m['role'] == 'admin').length;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    await _loadMembers();
    await _loadOverviewStats();
    await _loadRecentActivity();
    await _loadMembershipRequests();
  }

  Future<void> _openCommunicationSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CommunicationSheet(),
    );
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

  Future<void> _loadOverviewStats() async {
    final gymId = _gymId;
    if (gymId == null) return;

    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    try {
      final classes = await Supabase.instance.client
          .from('classes')
          .select('id')
          .eq('gym_id', gymId)
          .gte('starts_at', dayStart.toUtc().toIso8601String())
          .lt('starts_at', dayEnd.toUtc().toIso8601String());

      final classRows = List<Map<String, dynamic>>.from(classes);
      var bookingsCount = 0;

      for (final klass in classRows) {
        final count = await Supabase.instance.client
            .from('class_bookings')
            .select('id')
            .eq('class_id', klass['id'])
            .neq('status', 'cancelled')
            .count(CountOption.exact);

        bookingsCount += count.count;
      }

      final weekStart = dayStart.subtract(const Duration(days: 6));
      final weekClasses = await Supabase.instance.client
          .from('classes')
          .select('id, starts_at')
          .eq('gym_id', gymId)
          .gte('starts_at', weekStart.toUtc().toIso8601String())
          .lt('starts_at', dayEnd.toUtc().toIso8601String());

      final weeklyRows = List<Map<String, dynamic>>.from(weekClasses);
      final weeklyCounts = List<int>.filled(7, 0);

      for (final klass in weeklyRows) {
        final startsAt = DateTime.tryParse(
          klass['starts_at']?.toString() ?? '',
        )?.toLocal();

        if (startsAt == null) continue;

        final index = startsAt.difference(weekStart).inDays;
        if (index < 0 || index > 6) continue;

        final count = await Supabase.instance.client
            .from('class_bookings')
            .select('id')
            .eq('class_id', klass['id'])
            .neq('status', 'cancelled')
            .count(CountOption.exact);

        weeklyCounts[index] += count.count;
      }

      if (!mounted) return;
      setState(() {
        _todayClasses = classRows.length;
        _todayBookings = bookingsCount;
        _weeklyBookings = weeklyCounts;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todayClasses = 0;
        _todayBookings = 0;
        _weeklyBookings = List<int>.filled(7, 0);
      });
    }
  }

  Future<void> _loadMembershipRequests() async {
    final gymId = _gymId;
    if (gymId == null) return;

    try {
      final requests = await Supabase.instance.client
          .from('membership_requests')
          .select('id, user_id, plan_id, status, created_at')
          .eq('gym_id', gymId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final plans = await Supabase.instance.client
          .from('membership_plans')
          .select('id, name, plan_type, credits')
          .eq('gym_id', gymId);

      final planRows = List<Map<String, dynamic>>.from(plans);
      final requestRows = List<Map<String, dynamic>>.from(requests).map((row) {
        final userId = row['user_id']?.toString();
        final planId = row['plan_id']?.toString();

        final member = _members.firstWhere(
          (m) => m['id']?.toString() == userId,
          orElse: () => const {},
        );

        final plan = planRows.firstWhere(
          (p) => p['id']?.toString() == planId,
          orElse: () => const {},
        );

        return {
          ...row,
          'member_name':
              member['full_name']?.toString() ??
              member['email']?.toString() ??
              appStrings.member,
          'plan_name': plan['name']?.toString() ?? appStrings.plan,
          'plan_type': plan['plan_type']?.toString(),
          'credits': plan['credits'],
        };
      }).toList();

      if (!mounted) return;
      setState(() => _membershipRequests = requestRows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _membershipRequests = []);
    }
  }

  Future<void> _loadRecentActivity() async {
    final gymId = _gymId;
    if (gymId == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('class_bookings')
          .select('user_id, status, created_at, classes(title, starts_at)')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(5);

      final activity = List<Map<String, dynamic>>.from(rows)
          .where((row) {
            final klass = row['classes'];
            if (klass is! Map) return false;

            return _members.any((m) {
              return m['id']?.toString() == row['user_id']?.toString() &&
                  m['gym_id']?.toString() == gymId;
            });
          })
          .map((row) {
            final member = _members.firstWhere(
              (m) => m['id']?.toString() == row['user_id']?.toString(),
              orElse: () => const {},
            );

            return {
              ...row,
              'member_name':
                  member['full_name']?.toString() ??
                  member['email']?.toString() ??
                  appStrings.member,
            };
          })
          .toList();

      if (!mounted) return;
      setState(() => _recentActivity = activity);
    } catch (_) {
      if (!mounted) return;
      setState(() => _recentActivity = []);
    }
  }

  Future<void> _approveMembershipRequest(Map<String, dynamic> request) async {
    final userId = request['user_id']?.toString();
    final planId = request['plan_id']?.toString();
    final requestId = request['id']?.toString();

    if (userId == null || planId == null || requestId == null) return;

    try {
      await Supabase.instance.client.rpc(
        'assign_membership_plan',
        params: {'p_user_id': userId, 'p_plan_id': planId},
      );

      await Supabase.instance.client
          .from('membership_requests')
          .update({'status': 'approved'})
          .eq('id', requestId);

      await _loadDashboardData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.assignPlanError(e))));
    }
  }

  Future<void> _rejectMembershipRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString();

    if (requestId == null) return;

    try {
      await Supabase.instance.client
          .from('membership_requests')
          .update({'status': 'rejected'})
          .eq('id', requestId);

      await _loadDashboardData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.assignPlanError(e))));
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
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                border: Border.all(color: AppColors.border(context), width: 1),
                boxShadow: AppShadows.card(context),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.inviteAthlete.toUpperCase(),
                      style: _DashText.section.copyWith(
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appStrings.inviteAthleteDescription,
                      style: _DashText.subtle.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: fullName,
                      style: _DashText.body.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _dashboardInviteInput(
                        context,
                        appStrings.fullName,
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      style: _DashText.body.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _dashboardInviteInput(
                        context,
                        appStrings.athleteEmail,
                        Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      style: _DashText.body.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _dashboardInviteInput(
                        context,
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
                          style: _DashText.body.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: _dashboardInviteInput(
                            context,
                            appStrings.birthDate,
                            Icons.cake_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: _dashboardInviteInput(
                        context,
                        appStrings.role,
                        Icons.shield_outlined,
                      ),
                      style: _DashText.body.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700,
                      ),
                      dropdownColor: AppColors.surface(context),
                      items: [
                        DropdownMenuItem(
                          value: 'athlete',
                          child: Text(
                            appStrings.member,
                            style: _DashText.body.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'coach',
                          child: Text(
                            appStrings.coach,
                            style: _DashText.body.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text(
                            'Admin',
                            style: _DashText.body.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
                    AppButton(
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
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(AppRadii.sheet),
                border: Border.all(color: const Color(0xFF323232), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.editMember.toUpperCase(),
                    style: _DashText.section.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: fullName,
                    textCapitalization: TextCapitalization.words,
                    style: _DashText.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _dashboardInviteInput(
                      context,
                      appStrings.fullName,
                      Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    style: _DashText.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _dashboardInviteInput(
                      context,
                      appStrings.phone,
                      Icons.phone_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: birthDate,
                    readOnly: true,
                    style: _DashText.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _dashboardInviteInput(
                      context,
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
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
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
                        appStrings.assignPlan.toUpperCase(),
                        style: _DashText.title.copyWith(
                          color: AppColors.textPrimary(context),
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        appStrings.selectPlan.toUpperCase(),
                        style: _DashText.subtle.copyWith(
                          color: const Color(0xFFABABAB),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPlanId,
                        dropdownColor: const Color(0xFF171717),
                        iconEnabledColor: const Color(0xFFABABAB),
                        style: _DashText.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        hint: Text(
                          appStrings.selectPlan,
                          style: _DashText.body.copyWith(
                            color: const Color(0xFF8F96A3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        decoration: _dashInput(
                          appStrings.selectPlan,
                          Icons.card_membership_outlined,
                        ),
                        selectedItemBuilder: (context) {
                          return List<Map<String, dynamic>>.from(plans).map((
                            plan,
                          ) {
                            final name =
                                plan['name']?.toString() ?? appStrings.plan;
                            final credits = plan['credits'];

                            final label = credits == null
                                ? '$name · ${appStrings.unlimited}'
                                : '$name · $credits ${appStrings.creditsLower}';

                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                label,
                                style: _DashText.body.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }).toList();
                        },
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
                            child: Text(
                              label,
                              style: _DashText.body.copyWith(
                                color: Colors.white,
                              ),
                            ),
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
                        color: const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(AppRadii.sheet),
                        border: Border.all(
                          color: const Color(0xFF323232),
                          width: 1,
                        ),
                      ),
                      child: ListView(
                        shrinkWrap: false,
                        children: [
                          Center(
                            child: Container(
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A3A3A),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _MemberAvatar(
                                name: name,
                                avatarUrl: member['avatar_url']?.toString(),
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
                                      style: _DashText.title.copyWith(
                                        color: Colors.white,
                                      ),
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
                                dropdownColor: const Color(0xFF171717),
                                iconEnabledColor: const Color(0xFFABABAB),
                                style: _DashText.body.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
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
                                      '${appStrings.all} (${history.length})',
                                  selected: historyFilter == 'all',
                                  onTap: () => setSheetState(
                                    () => historyFilter = 'all',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MemberFilterChip(
                                  label:
                                      '${appStrings.attended.toUpperCase()} '
                                      '(${history.where((h) => h['status'] == 'attended').length})',
                                  selected: historyFilter == 'attended',
                                  onTap: () => setSheetState(
                                    () => historyFilter = 'attended',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MemberFilterChip(
                                  label:
                                      '${appStrings.noShow.toUpperCase()} '
                                      '(${history.where((h) => h['status'] == 'no_show').length})',
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
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          _DashboardHeader(
            gymName: widget.gymName,
            unreadNotifications: widget.unreadNotifications,
            onManagePlans: _openPlans,
            onOpenNotifications: widget.onOpenNotifications,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
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
              onRefresh: _loadDashboardData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                children: [
                  if (_selectedTab == _DashboardTab.overview) ...[
                    if (_membershipRequests.isNotEmpty) ...[
                      _MembershipRequestsCard(
                        requests: _membershipRequests,
                        onApprove: _approveMembershipRequest,
                        onReject: _rejectMembershipRequest,
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: appStrings.members,
                            value: '${_members.length}',
                            icon: Icons.groups_rounded,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _MetricCard(
                            label: appStrings.active,
                            value:
                                '${_members.where((m) => m['is_active'] == true).length}',
                            icon: Icons.verified_user_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: appStrings.bookingsToday,
                            value: '$_todayBookings',
                            icon: Icons.event_available_rounded,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _MetricCard(
                            label: appStrings.classesToday,
                            value: '$_todayClasses',
                            icon: Icons.fitness_center_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _WeeklyBookingsCard(bookings: _weeklyBookings),
                    const SizedBox(height: 14),
                    _RecentActivityCard(activity: _recentActivity),
                    const SizedBox(height: 14),
                    _CommunicationCard(
                      onSendNotification: _openCommunicationSheet,
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
                                width: 145,
                                height: 48,
                                child: FilledButton(
                                  onPressed: _openInviteMemberSheet,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.surfaceAlt(
                                      context,
                                    ),
                                    foregroundColor: AppColors.textPrimary(
                                      context,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(
                                        color: AppColors.border(context),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    appStrings.inviteAthlete,
                                    textAlign: TextAlign.center,
                                    style: _DashText.body.copyWith(
                                      color: AppColors.textPrimary(context),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: _DashText.body.copyWith(
                              color: AppColors.textPrimary(context),
                            ),
                            decoration: InputDecoration(
                              hintText: appStrings.searchMember,
                              hintStyle: GoogleFonts.barlowCondensed(
                                color: AppColors.textSecondary(context),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: AppColors.accent,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: AppColors.surfaceAlt(context),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 15,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.input,
                                ),
                                borderSide: BorderSide(
                                  color: AppColors.border(context),
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.input,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.accent,
                                  width: 1.2,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.input,
                                ),
                                borderSide: BorderSide(
                                  color: AppColors.border(context),
                                  width: 1,
                                ),
                              ),
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
    final membershipName = member['membership_name']?.toString();
    final creditsRemaining = member['credits_remaining'];
    final membershipLabel = membershipName == null || membershipName.isEmpty
        ? null
        : creditsRemaining == null
        ? '$membershipName · ${appStrings.unlimited}'
        : '$membershipName · $creditsRemaining ${appStrings.creditsLower}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceAlt(context),
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
                          style: _DashText.title.copyWith(
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _DashText.subtle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          membershipLabel == null
                              ? '$statusLabel · $role'
                              : '$membershipLabel · $statusLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _DashText.subtle.copyWith(
                            color: active
                                ? const Color(0xFFB59B6A)
                                : const Color(0xFF8F96A3),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: AppColors.textSecondary(context),
                    ),
                    onPressed: () => _openMemberActionsSheet(
                      context: context,
                      active: active,
                      isPending: isPending,
                      isDisabled: isDisabled,
                      onAssignPlan: onAssignPlan,
                      onToggleActive: onToggleActive,
                      onResendInvitation: onResendInvitation,
                      onDeletePendingMember: onDeletePendingMember,
                    ),
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

Future<void> _openMemberActionsSheet({
  required BuildContext context,
  required bool active,
  required bool isPending,
  required bool isDisabled,
  required Future<void> Function() onAssignPlan,
  required Future<void> Function() onToggleActive,
  required Future<void> Function() onResendInvitation,
  required Future<void> Function() onDeletePendingMember,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border(context), width: 1),
            boxShadow: AppShadows.card(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isDisabled)
                _MemberActionRow(
                  icon: Icons.card_membership_outlined,
                  label: appStrings.assignPlan,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await onAssignPlan();
                  },
                ),
              _MemberActionRow(
                icon: active
                    ? Icons.person_off_outlined
                    : Icons.person_add_alt_1_outlined,
                label: active
                    ? appStrings.deactivateMember
                    : appStrings.activateMember,
                danger: active,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await onToggleActive();
                },
              ),
              if (isPending)
                _MemberActionRow(
                  icon: Icons.mail_outline_rounded,
                  label: appStrings.resendInvitation,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await onResendInvitation();
                  },
                ),
              if (isPending)
                _MemberActionRow(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete invitation',
                  danger: true,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await onDeletePendingMember();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _MemberActionRow extends StatelessWidget {
  const _MemberActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 13, 4, 13),
        child: Row(
          children: [
            Icon(icon, color: danger ? AppColors.danger : AppColors.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: _DashText.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary(context),
            ),
          ],
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

InputDecoration _dashboardInviteInput(
  BuildContext context,
  String hint,
  IconData icon,
) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlowCondensed(
      color: AppColors.textSecondary(context),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    labelStyle: GoogleFonts.barlowCondensed(
      color: AppColors.textSecondary(context),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    floatingLabelStyle: GoogleFonts.barlowCondensed(
      color: AppColors.accent,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
    filled: true,
    fillColor: AppColors.surfaceAlt(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
  );
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
    labelStyle: GoogleFonts.barlowCondensed(
      color: const Color(0xFF8F96A3),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    floatingLabelStyle: GoogleFonts.barlowCondensed(
      color: const Color(0xFFB59B6A),
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
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

class _DashText {
  const _DashText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle section = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.8,
    height: 1.0,
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
      color: AppColors.surfaceAlt(context),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
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
                      style: _DashText.title.copyWith(
                        color: AppColors.textPrimary(context),
                      ),
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
                      style: _DashText.title.copyWith(
                        color: AppColors.textPrimary(context),
                        fontSize: 22,
                        letterSpacing: -0.2,
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
                        icon: Icons.notifications,
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: icon == Icons.notifications ? 32 : 28,
              color: AppColors.accent,
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -7,
              top: -7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
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
          color: selected ? Colors.white : AppColors.textSecondary(context),
          height: 1.0,
        ),
      ),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surfaceAlt(context),
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
              color: selected ? Colors.white : AppColors.textSecondary(context),
              height: 1.0,
            ),
          ),
        ),
      ),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surfaceAlt(context),
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
        color: AppColors.surface(context),
        border: Border.all(color: AppColors.border(context), width: 1),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card(context),
      ),
      child: child,
    );
  }
}

class _MembershipRequestsCard extends StatelessWidget {
  const _MembershipRequestsCard({
    required this.requests,
    required this.onApprove,
    required this.onReject,
  });

  final List<Map<String, dynamic>> requests;
  final Future<void> Function(Map<String, dynamic> request) onApprove;
  final Future<void> Function(Map<String, dynamic> request) onReject;

  String _planLabel(Map<String, dynamic> request) {
    final name = request['plan_name']?.toString() ?? appStrings.plan;
    final credits = request['credits'];

    if (credits == null) return '$name · ${appStrings.unlimited}';

    return '$name · $credits ${appStrings.creditsLower}';
  }

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.membershipRequests.toUpperCase(),
            style: _DashText.section,
          ),
          const SizedBox(height: 6),
          Text(
            appStrings.pendingApprovalCount(requests.length),
            style: _DashText.subtle,
          ),
          const SizedBox(height: 16),
          ...requests.map((request) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt(context),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Icon(
                          Icons.card_membership_outlined,
                          color: AppColors.accent,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request['member_name']?.toString() ??
                                  appStrings.member,
                              style: _DashText.body.copyWith(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(_planLabel(request), style: _DashText.subtle),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => onReject(request),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary(context),
                            side: BorderSide(color: AppColors.border(context)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            appStrings.reject.toUpperCase(),
                            style: _DashText.body.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onApprove(request),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            appStrings.approve.toUpperCase(),
                            style: _DashText.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label.toUpperCase(), style: _DashText.subtle),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(icon, size: 18, color: AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.barlowCondensed(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(context),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyBookingsCard extends StatelessWidget {
  const _WeeklyBookingsCard({required this.bookings});

  final List<int> bookings;

  @override
  Widget build(BuildContext context) {
    final maxValue = bookings.isEmpty
        ? 0
        : bookings.reduce(
            (value, element) => value > element ? value : element,
          );

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.weeklyBookings.toUpperCase(),
            style: _DashText.section,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final value = index < bookings.length ? bookings[index] : 0;
                final height = maxValue == 0
                    ? 10.0
                    : 18.0 + (value / maxValue) * 64.0;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: double.infinity,
                              height: height,
                              decoration: BoxDecoration(
                                color: value == maxValue && maxValue > 0
                                    ? AppColors.accent
                                    : AppColors.surfaceAlt(context),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: value == maxValue && maxValue > 0
                                      ? AppColors.accent
                                      : AppColors.border(context),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$value',
                          style: _DashText.subtle.copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunicationCard extends StatelessWidget {
  const _CommunicationCard({required this.onSendNotification});

  final VoidCallback onSendNotification;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.communicationTitle.toUpperCase(),
            style: _DashText.section,
          ),
          const SizedBox(height: 10),
          Text(
            appStrings.communicationSubtitle,
            style: _DashText.body.copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSendNotification,
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: Text(appStrings.sendNotification),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary(context),
                side: BorderSide(color: AppColors.border(context)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunicationSheet extends StatefulWidget {
  const _CommunicationSheet();

  @override
  State<_CommunicationSheet> createState() => _CommunicationSheetState();
}

class _CommunicationSheetState extends State<_CommunicationSheet> {
  final _title = TextEditingController();
  final _message = TextEditingController();
  String _recipients = 'all';
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _sendNotification() async {
    final title = _title.text.trim();
    final message = _message.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.notificationTitleRequired)),
      );
      return;
    }

    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.notificationMessageRequired)),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      final result = await Supabase.instance.client.functions.invoke(
        'admin-send-notification',
        body: {'title': title, 'body': message, 'audience': _recipients},
      );

      final data = Map<String, dynamic>.from(result.data as Map);
      final count = (data['count'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.notificationSentTo(count))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.notificationSendError(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _decoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: _DashText.subtle,
      filled: true,
      fillColor: AppColors.surfaceAlt(context),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.border(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottom + 18),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                appStrings.sendNotification.toUpperCase(),
                style: _DashText.section,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                style: _DashText.body.copyWith(
                  color: AppColors.textPrimary(context),
                ),
                decoration: _decoration(
                  context,
                  appStrings.notificationTitleLabel,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                minLines: 3,
                maxLines: 5,
                style: _DashText.body.copyWith(
                  color: AppColors.textPrimary(context),
                ),
                decoration: _decoration(
                  context,
                  appStrings.notificationMessageLabel,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                appStrings.notificationRecipientsLabel.toUpperCase(),
                style: _DashText.subtle,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                      ('all', appStrings.notificationAllMembers),
                      ('athlete', appStrings.notificationAthletes),
                      ('coach', appStrings.notificationCoaches),
                      ('admin', appStrings.notificationAdmins),
                    ].map((option) {
                      final selected = _recipients == option.$1;
                      return ChoiceChip(
                        label: Text(option.$2),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => _recipients = option.$1);
                        },
                        selectedColor: AppColors.accent.withValues(alpha: 0.18),
                        backgroundColor: AppColors.surfaceAlt(context),
                        side: BorderSide(
                          color: selected
                              ? AppColors.accent
                              : AppColors.border(context),
                        ),
                        labelStyle: _DashText.body.copyWith(
                          color: selected
                              ? AppColors.accent
                              : AppColors.textPrimary(context),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: _sending
                      ? appStrings.bookingLoadingClasses
                      : appStrings.sendNotification,
                  onPressed: _sending ? null : _sendNotification,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.activity});

  final List<Map<String, dynamic>> activity;

  String _memberName(Map<String, dynamic> row) {
    return row['member_name']?.toString().trim().isNotEmpty == true
        ? row['member_name'].toString()
        : appStrings.member;
  }

  String _activityText(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    final klass = row['classes'];
    final classTitle = klass is Map
        ? klass['title']?.toString() ?? appStrings.classFallback
        : appStrings.classFallback;

    final action = status == 'attended'
        ? appStrings.attended.toLowerCase()
        : status == 'no_show'
        ? appStrings.missed.toLowerCase()
        : appStrings.booked.toLowerCase();

    return '${_memberName(row)} $action $classTitle';
  }

  String _timeLabel(String? raw) {
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.recentActivity.toUpperCase(),
            style: _DashText.section,
          ),
          const SizedBox(height: 14),
          if (activity.isEmpty)
            Text(appStrings.noRecentActivity, style: _DashText.subtle)
          else
            ...activity.map((row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 7),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _activityText(row),
                        style: _DashText.body.copyWith(
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _timeLabel(row['created_at']?.toString()),
                      style: _DashText.subtle,
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
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context), width: 1),
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _DashText.subtle),
          const SizedBox(height: 5),
          Text(
            value,
            style: _DashText.body.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
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

  String get _formattedSubtitle {
    try {
      final dt = DateTime.parse(subtitle).toLocal();

      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];

      final day = days[dt.weekday - 1];
      final month = months[dt.month - 1];

      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');

      return '$day · ${dt.day} $month · $hh:$mm';
    } catch (_) {
      return subtitle;
    }
  }

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
          color: const Color(0xFF171717),
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
                  Text(_formattedSubtitle, style: _DashText.subtle),
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
