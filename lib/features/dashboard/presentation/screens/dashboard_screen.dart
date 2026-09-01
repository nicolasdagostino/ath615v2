import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../widgets/manage_plans_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_control_styles.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_async_state.dart';
import '../../../../core/widgets/app_admin_actions.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_large_form_sheet.dart';
import '../../../../core/widgets/app_keyboard_dismissible.dart';
import '../../../../core/widgets/app_primary_gym_header.dart';
import '../../../../core/widgets/app_section_chip.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../analytics/presentation/analytics_view.dart';
import '../../../booking/presentation/booking_occupancy.dart';
import '../../../booking/data/coach_briefing_repository.dart';
import '../../../booking/presentation/widgets/class_details_sheet.dart';
import '../../../members/data/member_coach_repository.dart';
import '../../../members/domain/member_coach_capability.dart';
import '../../../members/presentation/widgets/member_role_capability_section.dart';
import '../../../members/presentation/widgets/member_list_row.dart';
import '../../../members/presentation/widgets/member_filter_chip.dart';
import '../../../profile/presentation/screens/membership_screen.dart';
import '../../data/member_staff_notes_repository.dart';
import '../widgets/member_staff_notes_section.dart';
import '../../../profile/presentation/screens/gym_documents_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.gymName,
    required this.unreadNotifications,
    required this.onOpenNotifications,
    this.initialSection,
    this.initialMemberId,
  });

  final String? gymName;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;
  final String? initialSection;
  final String? initialMemberId;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}
enum _DashboardTab { overview, members, plans, analytics }

enum _MemberRoleFilter { all, athlete, coach, admin, withoutPlan }

bool adminMemberHasActivePlan(Map<String, dynamic> member) =>
    (member['membership_name']?.toString().trim() ?? '').isNotEmpty;

bool adminMemberIsWithoutActivePlan(Map<String, dynamic> member) =>
    member['role'] == 'athlete' &&
    member['is_active'] == true &&
    !adminMemberHasActivePlan(member);

String adminAccessRequestDisplayName(
  Map<String, dynamic>? profile, {
  required String fallback,
}) {
  final fullName = profile?['full_name']?.toString().trim() ?? '';
  if (fullName.isNotEmpty) return fullName;
  final email = profile?['email']?.toString().trim() ?? '';
  return email.isNotEmpty ? email : fallback;
}

DateTime? adminGymMemberCreatedAt(Map<String, dynamic> member) =>
    DateTime.tryParse(member['gym_member_created_at']?.toString() ?? '');

String adminMembershipRequestPriceLabel(Map<String, dynamic> request) {
  final rawAmount = request['amount_total'];
  final rawPrice = request['plan_price'];
  final amount = rawAmount is num
      ? rawAmount.toDouble() / 100
      : rawPrice is num
      ? rawPrice.toDouble()
      : double.tryParse(rawPrice?.toString() ?? '');
  if (amount == null) return '';
  final currency = request['currency']?.toString().toUpperCase() ?? '';
  return '${amount.toStringAsFixed(2)} $currency'.trim();
}

bool adminMembershipRequestNeedsAction(Map<String, dynamic> request) =>
    request['status'] == 'pending' &&
    request['payment_method'] == 'cash' &&
    request['payment_status'] == 'pending';

class _DashboardScreenState extends State<DashboardScreen> {
  final _search = TextEditingController();
  late final MemberCoachRepository _memberCoachRepository =
      SupabaseMemberCoachRepository(Supabase.instance.client);
  late final MemberStaffNotesRepository _memberStaffNotesRepository =
      SupabaseMemberStaffNotesRepository(Supabase.instance.client);

  bool _loadingMembers = true;
  String? _membersError;
  late _DashboardTab _selectedTab = widget.initialSection == 'membership'
      ? _DashboardTab.plans
      : widget.initialSection == 'members'
      ? _DashboardTab.members
      : widget.initialSection == 'analytics'
      ? _DashboardTab.analytics
      : _DashboardTab.overview;
  _MemberRoleFilter _roleFilter = _MemberRoleFilter.all;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _membershipRequests = [];
  List<Map<String, dynamic>> _gymJoinRequests = [];
  String? _processingMembershipRequestId;
  String? _processingGymJoinRequestId;
  String? _processingGymJoinRequestAction;
  String? _gymId;
  int _todayBookings = 0;
  int _todayClasses = 0;
  int _todayCapacity = 0;
  List<int> _weeklyBookings = List<int>.filled(7, 0);
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _todayClassRows = [];
  bool _initialMemberHandled = false;

  int get _athletesCount =>
      _members.where((m) => m['role'] == 'athlete').length;

  int get _coachesCount => _members.where(memberHasCoachCapability).length;

  int get _adminsCount => _members.where((m) => m['role'] == 'admin').length;

  List<Map<String, dynamic>> get _membersWithoutPlan =>
      _members.where(adminMemberIsWithoutActivePlan).toList();

  List<Map<String, dynamic>> get _membershipsExpiringSoon {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final limit = today.add(const Duration(days: 8));

    final members = _members.where((m) {
      if (m['role'] != 'athlete' || m['is_active'] != true) return false;

      final membershipName = m['membership_name']?.toString().trim() ?? '';
      if (membershipName.isEmpty) return false;

      final rawExpiresAt = m['membership_expires_at']?.toString();
      if (rawExpiresAt == null || rawExpiresAt.isEmpty) return false;

      final expiresAt = DateTime.tryParse(rawExpiresAt)?.toLocal();
      if (expiresAt == null) return false;

      final expiryDay = DateTime(
        expiresAt.year,
        expiresAt.month,
        expiresAt.day,
      );

      return !expiryDay.isBefore(today) && expiryDay.isBefore(limit);
    }).toList();

    members.sort((a, b) {
      final aDate = DateTime.tryParse(
        a['membership_expires_at']?.toString() ?? '',
      );
      final bDate = DateTime.tryParse(
        b['membership_expires_at']?.toString() ?? '',
      );

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });

    return members;
  }

  List<Map<String, dynamic>> get _activeMembershipMembers {
    return _members.where((m) {
      final membershipName = m['membership_name']?.toString().trim() ?? '';
      return m['role'] == 'athlete' &&
          m['is_active'] == true &&
          membershipName.isNotEmpty;
    }).toList();
  }

  String get _mostUsedPlanName {
    final counts = <String, int>{};

    for (final member in _activeMembershipMembers) {
      final name = member['membership_name']?.toString().trim();
      if (name == null || name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }

    if (counts.isEmpty) return '-';

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries.first.key;
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    await _loadMembers();

    final initialMemberId = widget.initialMemberId;
    if (!_initialMemberHandled && initialMemberId != null && mounted) {
      _initialMemberHandled = true;
      final member = _members.where(
        (candidate) => candidate['id']?.toString() == initialMemberId,
      );
      if (member.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openMember(member.first);
        });
      }
    }

    await Future.wait([
      _loadGymJoinRequests(),
      _loadMembershipRequests(),
      _loadOverviewStats(),
      _loadRecentActivity(),
    ]);
  }

  Future<void> _openCommunicationSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .9,
        child: _CommunicationSheet(),
      ),
    );
  }

  Future<void> _openCoachClass(Map<String, dynamic> row) async {
    await showClassDetailsSheet(
      context: context,
      client: Supabase.instance.client,
      klass: row,
      actionLabel: '',
      onAction: null,
      coachRepository: SupabaseCoachBriefingRepository(
        Supabase.instance.client,
      ),
      onMemberTap: (memberId) {
        final member = _members.where(
          (candidate) => candidate['id']?.toString() == memberId,
        );
        if (member.isNotEmpty) _openMember(member.first);
      },
    );
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loadingMembers = true;
      _membersError = null;
    });

    try {
      final membersFuture = Supabase.instance.client.functions.invoke(
        'admin-list-members',
      );
      final capabilitiesFuture = _memberCoachRepository.listCapabilities();
      final result = await membersFuture;
      final capabilities = await capabilitiesFuture;

      final data = Map<String, dynamic>.from(result.data as Map);
      final sourceMembers = List<Map<String, dynamic>>.from(
        data['members'] as List,
      );
      final members = sourceMembers.map((member) {
        final memberId = member['id']?.toString();
        return memberWithCoachCapability(
          member,
          memberId == null
              ? memberHasCoachCapability(member)
              : capabilities[memberId] ?? memberHasCoachCapability(member),
        );
      }).toList();

      final gymId = members.isEmpty
          ? _gymId
          : members.first['gym_id']?.toString();

      if (!mounted) return;
      setState(() {
        _gymId = gymId;
        _members = members;
        _membersError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _membersError = appStrings.loadMembersError(e));
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
          .select(
            'id, title, starts_at, duration_minutes, capacity, recurring_id, '
            'program_id, coach_id, programs(name, image_url), '
            'coach:profiles!classes_coach_id_fkey(full_name, avatar_url)',
          )
          .eq('gym_id', gymId)
          .gte('starts_at', dayStart.toUtc().toIso8601String())
          .lt('starts_at', dayEnd.toUtc().toIso8601String())
          .order('starts_at', ascending: true);

      final classRows = List<Map<String, dynamic>>.from(classes);
      final capacityCount = classRows.fold<int>(
        0,
        (sum, klass) => sum + ((klass['capacity'] as int?) ?? 0),
      );
      final todayClassIds = classRows.map((row) => row['id']).toList();
      final todayBookingRows = todayClassIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client
                  .from('class_bookings')
                  .select(
                    'id, class_id, user_id, guest_name, is_guest, status, created_at',
                  )
                  .inFilter('class_id', todayClassIds)
                  .neq('status', 'cancelled'),
            );
      final todayWaitlistRows = todayClassIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client
                  .from('class_waitlist')
                  .select('class_id, user_id, created_at')
                  .inFilter('class_id', todayClassIds)
                  .order('created_at', ascending: true),
            );
      final bookingsCount = todayBookingRows.length;

      for (final klass in classRows) {
        final classId = klass['id']?.toString();
        klass['booking_rows'] = todayBookingRows
            .where((row) => row['class_id']?.toString() == classId)
            .toList();
        klass['waitlist_rows'] = todayWaitlistRows
            .where((row) => row['class_id']?.toString() == classId)
            .toList();
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

      final weeklyClassIds = weeklyRows.map((row) => row['id']).toList();
      final weeklyBookingRows = weeklyClassIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client
                  .from('class_bookings')
                  .select('class_id')
                  .inFilter('class_id', weeklyClassIds)
                  .neq('status', 'cancelled'),
            );
      final weeklyCountByClass = <String, int>{};
      for (final booking in weeklyBookingRows) {
        final classId = booking['class_id']?.toString();
        if (classId != null) {
          weeklyCountByClass[classId] = (weeklyCountByClass[classId] ?? 0) + 1;
        }
      }

      for (final klass in weeklyRows) {
        final startsAt = DateTime.tryParse(
          klass['starts_at']?.toString() ?? '',
        )?.toLocal();

        if (startsAt == null) continue;

        final index = startsAt.difference(weekStart).inDays;
        if (index < 0 || index > 6) continue;

        weeklyCounts[index] += weeklyCountByClass[klass['id']?.toString()] ?? 0;
      }

      if (!mounted) return;
      setState(() {
        _todayClasses = classRows.length;
        _todayBookings = bookingsCount;
        _todayCapacity = capacityCount;
        _todayClassRows = classRows;
        _weeklyBookings = weeklyCounts;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todayClasses = 0;
        _todayBookings = 0;
        _todayCapacity = 0;
        _todayClassRows = [];
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
          .select(
            'id, user_id, plan_id, status, payment_method, payment_status, '
            'amount_total, currency, created_at',
          )
          .eq('gym_id', gymId)
          .eq('status', 'pending')
          .eq('payment_method', 'cash')
          .eq('payment_status', 'pending')
          .order('created_at', ascending: false);

      final plans = await Supabase.instance.client
          .from('membership_plans')
          .select('id, name, plan_type, credits, price, currency')
          .eq('gym_id', gymId);

      final planRows = List<Map<String, dynamic>>.from(plans);
      final requestRows = List<Map<String, dynamic>>.from(requests)
          .where(adminMembershipRequestNeedsAction)
          .map((row) {
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
              'plan_price': plan['price'],
              'currency': row['currency'] ?? plan['currency'],
            };
          })
          .toList();

      if (!mounted) return;
      setState(() => _membershipRequests = requestRows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _membershipRequests = []);
    }
  }

  Future<void> _loadGymJoinRequests() async {
    final gymId = _gymId;
    if (gymId == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('gym_join_requests')
          .select('id, user_id, status, created_at')
          .eq('gym_id', gymId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final requestRows = List<Map<String, dynamic>>.from(rows);
      final userIds = requestRows
          .map((row) => row['user_id']?.toString())
          .whereType<String>()
          .toList();

      final profiles = userIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client
                  .from('profiles')
                  .select('id, full_name, email, phone, birth_date, avatar_url')
                  .inFilter('id', userIds),
            );

      final profileById = {
        for (final profile in profiles) profile['id'].toString(): profile,
      };

      final requests = requestRows.map((row) {
        final userId = row['user_id']?.toString();
        final profile = userId == null ? null : profileById[userId];

        return {
          ...row,
          'member_name': _requesterName(profile),
          'member_email': profile?['email']?.toString(),
          'member_phone': profile?['phone']?.toString(),
          'member_birth_date': profile?['birth_date']?.toString(),
          'member_avatar_url': profile?['avatar_url']?.toString(),
        };
      }).toList();

      if (!mounted) return;
      setState(() => _gymJoinRequests = requests);
    } catch (_) {
      if (!mounted) return;
      setState(() => _gymJoinRequests = []);
    }
  }

  String _requesterName(Map<String, dynamic>? profile) {
    return adminAccessRequestDisplayName(profile, fallback: appStrings.member);
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

  Future<void> _approveGymJoinRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString();
    if (requestId == null) return;

    setState(() {
      _processingGymJoinRequestId = requestId;
      _processingGymJoinRequestAction = 'approve';
    });

    try {
      await Supabase.instance.client.rpc(
        'approve_gym_join_request',
        params: {'p_request_id': requestId},
      );

      await Supabase.instance.client.functions.invoke('send-notifications');
      await _loadDashboardData();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.memberJoinedGym)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.joinRequestActionError(e))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingGymJoinRequestId = null;
          _processingGymJoinRequestAction = null;
        });
      }
    }
  }

  Future<void> _rejectGymJoinRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString();
    if (requestId == null) return;

    setState(() {
      _processingGymJoinRequestId = requestId;
      _processingGymJoinRequestAction = 'reject';
    });

    try {
      await Supabase.instance.client.rpc(
        'reject_gym_join_request',
        params: {'p_request_id': requestId},
      );

      await Supabase.instance.client.functions.invoke('send-notifications');
      await _loadDashboardData();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.joinRequestRejected)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.joinRequestActionError(e))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingGymJoinRequestId = null;
          _processingGymJoinRequestAction = null;
        });
      }
    }
  }

  Future<void> _approveMembershipRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString();

    if (requestId == null) return;

    final method = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppAdminActionSheet(
        accentColor: AppColors.primary,
        // Each action returns its value; AppAdminActionSheet invokes onClose
        // before onTap, so this callback must not pop twice.
        onClose: () {},
        actions: [
          AppAdminAction(
            icon: Icons.payments_outlined,
            label: appStrings.cash,
            onTap: () => Navigator.pop(sheetContext, 'cash'),
          ),
          AppAdminAction(
            icon: Icons.phone_iphone_rounded,
            label: appStrings.bizum,
            onTap: () => Navigator.pop(sheetContext, 'bizum'),
          ),
        ],
      ),
    );
    if (method == null || !mounted) return;

    setState(() => _processingMembershipRequestId = requestId);

    try {
      await Supabase.instance.client.rpc(
        'confirm_in_person_membership_payment',
        params: {'p_request_id': requestId, 'p_manual_payment_method': method},
      );

      await Supabase.instance.client.functions.invoke('send-notifications');

      await _loadDashboardData();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.planAssigned)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.assignPlanError(e))));
    } finally {
      if (mounted) setState(() => _processingMembershipRequestId = null);
    }
  }

  Future<void> _rejectMembershipRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString();

    if (requestId == null) return;

    setState(() => _processingMembershipRequestId = requestId);

    try {
      await Supabase.instance.client.rpc(
        'reject_membership_request',
        params: {'p_request_id': requestId},
      );

      await _loadDashboardData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.assignPlanError(e))));
    } finally {
      if (mounted) setState(() => _processingMembershipRequestId = null);
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
    final name = (member['full_name'] ?? member['email'] ?? appStrings.member)
        .toString();

    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: appStrings.deleteInvitationQuestion,
      message: appStrings.deleteInvitationMessage(name),
      confirmLabel: appStrings.delete,
      cancelLabel: appStrings.cancel,
    );

    if (!confirmed) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'admin-delete-pending-member',
        body: {'member_id': member['id'].toString()},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.invitationDeleted)));

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

    await showAppLargeFormSheet<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Scaffold(
              backgroundColor: AppColors.background(context),
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(58),
                child: AppFormHeader(
                  title: appStrings.inviteAthlete,
                  onClose: () => Navigator.of(context).pop(),
                  accentColor: AppColors.primary,
                ),
              ),
              body: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: AppSpacing.screenX,
                  right: AppSpacing.screenX,
                  top: AppSpacing.md,
                  bottom:
                      MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.inviteAthleteDescription,
                      style: _DashText.subtle.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: fullName,
                      style: appFormValueStyle(context),
                      decoration: appFormInput(
                        context,
                        hintText: appStrings.fullName,
                        icon: Icons.person_outline,
                        accentColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      style: appFormValueStyle(context),
                      decoration: appFormInput(
                        context,
                        hintText: appStrings.athleteEmail,
                        icon: Icons.email_outlined,
                        accentColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      style: appFormValueStyle(context),
                      decoration: appFormInput(
                        context,
                        hintText: appStrings.phone,
                        icon: Icons.phone_outlined,
                        accentColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: inviting ? null : () => _pickBirthDate(birthDate),
                      child: IgnorePointer(
                        child: TextField(
                          controller: birthDate,
                          style: appFormValueStyle(context),
                          decoration: appFormInput(
                            context,
                            hintText: appStrings.birthDate,
                            icon: Icons.cake_outlined,
                            accentColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: appFormInput(
                        context,
                        hintText: appStrings.role,
                        icon: Icons.shield_outlined,
                        accentColor: AppColors.primary,
                      ),
                      style: appFormValueStyle(context),
                      dropdownColor: AppColors.surface(context),
                      items: [
                        DropdownMenuItem(
                          value: 'athlete',
                          child: Text(
                            appStrings.member,
                            style: appFormValueStyle(context),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'coach',
                          child: Text(
                            appStrings.coachRoleLabel,
                            style: appFormValueStyle(context),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text(
                            appStrings.adminRoleLabel,
                            style: appFormValueStyle(context),
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
                    AppFormSubmitButton(
                      label: appStrings.inviteAthlete,
                      loading: inviting,
                      enabled: !inviting,
                      accentColor: AppColors.primary,
                      icon: Icons.add_rounded,
                      onPressed: () async {
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
          return memberHasCoachCapability(m);

        case _MemberRoleFilter.admin:
          return role == 'admin';

        case _MemberRoleFilter.withoutPlan:
          return adminMemberIsWithoutActivePlan(m);

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

  Future<void> openLegacyEditMemberSheet(Map<String, dynamic> member) async {
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
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(AppRadii.sheet),
                border: Border.all(color: AppColors.border(context), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.editMember.toUpperCase(),
                    style: _DashText.section.copyWith(
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: fullName,
                    textCapitalization: TextCapitalization.words,
                    style: _DashText.body.copyWith(
                      color: AppColors.textPrimary(context),
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
                      color: AppColors.textPrimary(context),
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
                      color: AppColors.textPrimary(context),
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

  Future<Map<String, dynamic>> _loadMemberMembershipData(
    String memberId,
  ) async {
    final membershipRows = await Supabase.instance.client
        .from('member_memberships')
        .select(
          'id, credits_remaining, starts_at, expires_at, status, is_active, '
          'created_at, membership_plans(name, plan_type, credits)',
        )
        .eq('user_id', memberId)
        .eq('is_active', true)
        .inFilter('status', ['active', 'scheduled'])
        .order('created_at', ascending: false);

    final memberships = List<Map<String, dynamic>>.from(membershipRows);

    Map<String, dynamic>? membership;

    for (final row in memberships) {
      final plan = row['membership_plans'] as Map?;
      final isActiveUnlimited =
          row['status'] == 'active' && plan?['plan_type'] == 'unlimited';

      if (isActiveUnlimited) {
        membership = row;
        break;
      }
    }

    membership ??= memberships
        .where((row) => row['status'] == 'active')
        .cast<Map<String, dynamic>>()
        .firstOrNull;

    membership ??= memberships.firstOrNull;

    return {'membership': membership, 'memberships': memberships};
  }

  Future<Map<String, dynamic>> _loadMemberStats(String memberId) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonthStart = DateTime(now.year, now.month + 1);

    final attended = await Supabase.instance.client
        .from('class_bookings')
        .select('id')
        .eq('user_id', memberId)
        .eq('status', 'attended');

    final monthRows = await Supabase.instance.client
        .from('class_bookings')
        .select('status, classes!inner(starts_at)')
        .eq('user_id', memberId)
        .inFilter('status', ['attended', 'no_show'])
        .gte('classes.starts_at', monthStart.toUtc().toIso8601String())
        .lt('classes.starts_at', nextMonthStart.toUtc().toIso8601String());

    final lastAttendanceRows = await Supabase.instance.client
        .from('class_bookings')
        .select('classes!inner(starts_at)')
        .eq('user_id', memberId)
        .eq('status', 'attended')
        .order('starts_at', referencedTable: 'classes', ascending: false)
        .limit(1);

    final monthBookings = List<Map<String, dynamic>>.from(monthRows);
    final lastAttendance = List<Map<String, dynamic>>.from(lastAttendanceRows);

    return {
      'attended_count': List<Map<String, dynamic>>.from(attended).length,
      'attended_this_month': monthBookings
          .where((row) => row['status']?.toString() == 'attended')
          .length,
      'no_show_this_month': monthBookings
          .where((row) => row['status']?.toString() == 'no_show')
          .length,
      'last_attendance': lastAttendance.isEmpty
          ? null
          : (lastAttendance.first['classes'] as Map?)?['starts_at']?.toString(),
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
        SnackBar(content: Text(appStrings.reactivateMemberError(e))),
      );
    }
  }

  Future<void> _updateMemberRole({
    required Map<String, dynamic> member,
    required String role,
    required String currentSelectedRole,
    required void Function(void Function()) setSheetState,
  }) async {
    if (role == currentSelectedRole) return;

    try {
      await Supabase.instance.client.rpc(
        'update_member_role',
        params: {'p_member_id': member['id'], 'p_role': role},
      );

      final updatedMember = memberWithRole(member, role);
      member
        ..clear()
        ..addAll(updatedMember);

      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentUserId = currentUser?.id;
      final currentUserEmail = currentUser?.email?.trim().toLowerCase();
      final memberId = member['id']?.toString();
      final memberEmail = member['email']?.toString().trim().toLowerCase();

      final changedOwnRole =
          (currentUserId != null && memberId == currentUserId) ||
          (currentUserEmail != null && memberEmail == currentUserEmail);

      if (changedOwnRole && role != 'admin') {
        await AuthRepository(Supabase.instance.client).signOut();

        if (!mounted) return;
        context.go('/login');
        return;
      }

      if (!mounted) return;

      setSheetState(() {});

      setState(() {
        final index = _members.indexWhere((m) => m['id'] == member['id']);

        if (index != -1) {
          _members[index] = memberWithRole(_members[index], role);
        }
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.roleUpdated)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.roleUpdateError(e))));
    }
  }

  Future<void> _updateMemberCoachCapability({
    required Map<String, dynamic> member,
    required bool isCoach,
    required void Function(void Function()) setSheetState,
  }) async {
    final memberId = member['id']?.toString();
    if (memberId == null || memberId.isEmpty) return;

    try {
      final updated = await _memberCoachRepository.setCapability(
        memberId: memberId,
        isCoach: isCoach,
      );
      if (!updated) throw StateError('member_not_updated');

      final updatedMember = memberWithCoachCapability(member, isCoach);
      member
        ..clear()
        ..addAll(updatedMember);

      if (!mounted) return;
      setSheetState(() {});
      setState(() {
        final index = _members.indexWhere(
          (candidate) => candidate['id']?.toString() == memberId,
        );
        if (index != -1) {
          _members[index] = memberWithCoachCapability(_members[index], isCoach);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.coachCapabilityUpdated)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.coachCapabilityUpdateError(error))),
      );
    }
  }

  Future<bool> _openAssignPlan(String userId) async {
    final rootContext = context;
    final gymId = _gymId;
    if (gymId == null) return false;

    final client = Supabase.instance.client;

    final plans = await client
        .from('membership_plans')
        .select('id, name, plan_type, credits')
        .eq('gym_id', gymId)
        .eq('is_active', true);

    String? selectedPlanId;
    var saving = false;

    if (!mounted) return false;

    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  decoration: BoxDecoration(
                    color: AppColors.surface(modalContext),
                    borderRadius: BorderRadius.circular(AppRadii.sheet),
                    border: Border.all(
                      color: AppColors.border(modalContext),
                      width: 1,
                    ),
                    boxShadow: AppShadows.card(modalContext),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Text(
                        appStrings.assignPlan.toUpperCase(),
                        style: _DashText.title.copyWith(
                          color: AppColors.textPrimary(modalContext),
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        appStrings.selectPlan.toUpperCase(),
                        style: _DashText.subtle.copyWith(
                          color: AppColors.textSecondary(modalContext),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (plans.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt(modalContext),
                            borderRadius: BorderRadius.circular(AppRadii.input),
                            border: Border.all(
                              color: AppColors.border(modalContext),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      appStrings.noActivePlansAvailable,
                                      style: _DashText.body.copyWith(
                                        color: AppColors.textPrimary(
                                          modalContext,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      appStrings.createPlanBeforeAssigning,
                                      style: _DashText.subtle.copyWith(
                                        color: AppColors.textSecondary(
                                          modalContext,
                                        ),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...List<Map<String, dynamic>>.from(plans).map((plan) {
                          final id = plan['id'].toString();
                          final selected = selectedPlanId == id;
                          final name =
                              plan['name']?.toString() ?? appStrings.plan;
                          final credits = plan['credits'];
                          final metadata = credits == null
                              ? appStrings.unlimited
                              : '$credits ${appStrings.creditsLower}';
                          return Material(
                            color: selected
                                ? AppColors.primary.withValues(alpha: .1)
                                : Colors.transparent,
                            child: InkWell(
                              onTap: saving
                                  ? null
                                  : () => setSheetState(
                                      () => selectedPlanId = id,
                                    ),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 64,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppColors.border(modalContext),
                                      width: .7,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style:
                                                AppTypography.body(
                                                  modalContext,
                                                ).copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          Text(
                                            metadata,
                                            style: AppTypography.bodySecondary(
                                              modalContext,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      selected
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.textSecondary(
                                              modalContext,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 18),
                      AppFormSubmitButton(
                        label: appStrings.assign,
                        loading: saving,
                        enabled: selectedPlanId != null && !saving,
                        accentColor: AppColors.primary,
                        onPressed: () async {
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

                            if (!modalContext.mounted) return;

                            Navigator.pop(modalContext, true);

                            if (!rootContext.mounted) return;
                          } catch (e) {
                            if (!modalContext.mounted) return;

                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(
                                content: Text(appStrings.assignPlanError(e)),
                              ),
                            );
                          } finally {
                            if (modalContext.mounted) {
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

    return assigned ?? false;
  }

  String _memberMembershipStatusLabel(String? status) {
    switch (status) {
      case 'active':
        return appStrings.active;
      case 'scheduled':
        return appStrings.scheduled;
      case 'exhausted':
        return appStrings.exhausted;
      case 'expired':
        return appStrings.expired;
      case 'cancelled':
        return appStrings.cancelled;
      case 'replaced':
        return appStrings.replaced;
      default:
        return status ?? '-';
    }
  }

  IconData _memberMembershipStatusIcon(String? status) {
    switch (status) {
      case 'active':
        return Icons.check_circle_rounded;
      case 'scheduled':
        return Icons.schedule_rounded;
      case 'exhausted':
        return Icons.inventory_2_rounded;
      case 'expired':
        return Icons.event_busy_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'replaced':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.card_membership_rounded;
    }
  }

  Color _memberMembershipStatusColor(BuildContext context, String? status) {
    switch (status) {
      case 'active':
        return const Color(0xFF2EAD68);
      case 'scheduled':
        return const Color(0xFF3A7BD5);
      case 'exhausted':
        return const Color(0xFFE09B2D);
      case 'expired':
      case 'cancelled':
      case 'replaced':
        return AppColors.textSecondary(context);
      default:
        return AppColors.primary;
    }
  }

  String _formatMembershipClassDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';

    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '—';

    final locale = appStrings.isEs ? 'es' : 'en';
    return DateFormat('d MMM yyyy · HH:mm', locale).format(date);
  }

  Future<void> _openMemberMembershipDetails(
    Map<String, dynamic> membership,
  ) async {
    final planData = membership['membership_plans'];
    final plan = planData is Map
        ? Map<String, dynamic>.from(planData)
        : <String, dynamic>{};

    final status = membership['status']?.toString();
    final planName = plan['name']?.toString() ?? appStrings.plan;
    final remainingCredits = membership['credits_remaining'];
    final totalCredits = plan['credits'];

    final creditsLabel = remainingCredits == null
        ? appStrings.unlimited
        : totalCredits == null
        ? remainingCredits.toString()
        : '$remainingCredits / $totalCredits';

    List<Map<String, dynamic>> attendedClasses = [];
    Object? loadError;

    try {
      final rows = await Supabase.instance.client
          .from('class_bookings')
          .select('id, status, classes(title, starts_at)')
          .eq('membership_id', membership['id'])
          .eq('status', 'attended')
          .order('created_at', ascending: false);

      attendedClasses = List<Map<String, dynamic>>.from(rows);
    } catch (error) {
      loadError = error;
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final statusColor = _memberMembershipStatusColor(sheetContext, status);

        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
            ),
            margin: const EdgeInsets.fromLTRB(12, 72, 12, 12),
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(sheetContext),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.border(sheetContext),
                width: 1,
              ),
              boxShadow: AppShadows.card(sheetContext),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border(sheetContext),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        _memberMembershipStatusIcon(status),
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            planName,
                            style: _DashText.title.copyWith(
                              color: AppColors.textPrimary(sheetContext),
                              fontSize: 26,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _memberMembershipStatusLabel(status).toUpperCase(),
                            style: _DashText.section.copyWith(
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _MemberDetailCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MemberDetailInfoRow(
                        label: appStrings.purchased,
                        value: _formatDate(
                          membership['created_at']?.toString(),
                        ),
                      ),
                      _MemberDetailInfoRow(
                        label: appStrings.starts,
                        value: _formatDate(membership['starts_at']?.toString()),
                      ),
                      _MemberDetailInfoRow(
                        label: appStrings.expires,
                        value: _formatDate(
                          membership['expires_at']?.toString(),
                        ),
                      ),
                      _MemberDetailInfoRow(
                        label: appStrings.credits,
                        value: creditsLabel,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  appStrings.classesAttended.toUpperCase(),
                  style: _DashText.section.copyWith(
                    color: AppColors.textPrimary(sheetContext),
                  ),
                ),
                const SizedBox(height: 12),
                if (loadError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface(sheetContext),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border(sheetContext)),
                    ),
                    child: Text(appStrings.noClasses, style: _DashText.subtle),
                  )
                else if (attendedClasses.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface(sheetContext),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border(sheetContext)),
                    ),
                    child: Text(appStrings.noClasses, style: _DashText.subtle),
                  )
                else
                  ...attendedClasses.map((booking) {
                    final classData = booking['classes'];
                    final classRow = classData is Map
                        ? Map<String, dynamic>.from(classData)
                        : <String, dynamic>{};

                    final title =
                        classRow['title']?.toString() ??
                        appStrings.classFallback;

                    final startsAt = classRow['starts_at']?.toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                      decoration: BoxDecoration(
                        color: AppColors.surface(sheetContext),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.border(sheetContext),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.calendar_today_rounded,
                              color: statusColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: _DashText.body.copyWith(
                                    color: AppColors.textPrimary(sheetContext),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatMembershipClassDateTime(startsAt),
                                  style: _DashText.subtle,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.check_circle_rounded,
                            color: statusColor,
                            size: 20,
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openMember(Map<String, dynamic> member) {
    String historyFilter = 'all';
    var updatingCoach = false;
    var memberDirty = false;
    var savingMember = false;
    final memberName = TextEditingController(
      text: member['full_name']?.toString() ?? '',
    );
    final memberPhone = TextEditingController(
      text: member['phone']?.toString() ?? '',
    );
    final memberBirthDate = TextEditingController(
      text: member['birth_date']?.toString() ?? '',
    );
    final memberEmail = TextEditingController(
      text: member['email']?.toString() ?? '',
    );

    Future<List<dynamic>> loadMemberData() {
      return Future.wait([
        _loadMemberHistory(member['id'].toString()),
        _loadMemberMembershipData(member['id'].toString()),
        _loadMemberStats(member['id'].toString()),
      ]);
    }

    var memberDataFuture = loadMemberData();

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
            final active = member['is_active'] == true;
            return FutureBuilder<List<dynamic>>(
              future: memberDataFuture,
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

                final membershipPlan = membership?['membership_plans'] as Map?;
                final membershipPlanName =
                    membershipPlan?['name']?.toString() ?? appStrings.plan;
                final membershipStatus =
                    membership?['status']?.toString() ?? '';
                final membershipRemaining = membership?['credits_remaining'];
                final membershipTotalCredits = membershipPlan?['credits'];

                final membershipCreditsLabel = membershipRemaining == null
                    ? appStrings.unlimited
                    : membershipTotalCredits == null
                    ? membershipRemaining.toString()
                    : '$membershipRemaining / $membershipTotalCredits';

                final stats = snapshot.hasData
                    ? snapshot.data![2] as Map<String, dynamic>
                    : <String, dynamic>{};
                final attendedCount = stats['attended_count'] as int? ?? 0;
                final attendedThisMonth =
                    stats['attended_this_month'] as int? ?? 0;
                final noShowsThisMonth =
                    stats['no_show_this_month'] as int? ?? 0;
                final lastAttendance = stats['last_attendance']?.toString();
                final gymMemberCreatedAt = adminGymMemberCreatedAt(member);

                return AppKeyboardDismissible(
                  child: Padding(
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
                        color: AppColors.surface(context),
                        borderRadius: BorderRadius.circular(AppRadii.sheet),
                        border: Border.all(
                          color: AppColors.border(context),
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
                                color: AppColors.border(context),
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: _DashText.title.copyWith(
                                              color: AppColors.textPrimary(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: active
                                                ? AppColors.primary.withValues(
                                                    alpha: 0.14,
                                                  )
                                                : AppColors.surfaceAlt(context),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: active
                                                  ? AppColors.primary
                                                        .withValues(alpha: 0.45)
                                                  : AppColors.border(context),
                                            ),
                                          ),
                                          child: Text(
                                            (active
                                                    ? appStrings.active
                                                    : appStrings.inactive)
                                                .toUpperCase(),
                                            style: _DashText.subtle.copyWith(
                                              color: active
                                                  ? AppColors.primary
                                                  : AppColors.textSecondary(
                                                      context,
                                                    ),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (selectedRole == 'admin'
                                          ? appStrings.adminRoleLabel
                                          : selectedRole == 'coach'
                                          ? appStrings.coachRoleLabel
                                          : appStrings.member),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _DashText.subtle.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (gymMemberCreatedAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '${appStrings.memberSince.toUpperCase()} · '
                                        '${_formatDate(gymMemberCreatedAt.toIso8601String())}',
                                        key: const ValueKey(
                                          'member-since-label',
                                        ),
                                        style: AppTypography.helper(context),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _MemberOverviewCard(
                            attendedThisMonth: attendedThisMonth,
                            noShowsThisMonth: noShowsThisMonth,
                            lastAttendance: lastAttendance == null
                                ? appStrings.noAttendancesYet
                                : _formatDate(lastAttendance),
                            totalAttended: attendedCount,
                          ),
                          const SizedBox(height: 18),
                          _MemberMilestoneCard(attendedCount: attendedCount),
                          const SizedBox(height: 18),
                          _MemberDetailCard(
                            child: MemberStaffNotesSection(
                              memberUserId: member['id'].toString(),
                              repository: _memberStaffNotesRepository,
                              canManage: true,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _MemberDetailCard(
                            child: MemberDocumentsSection(
                              memberUserId: member['id'].toString(),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _MemberDetailCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appStrings.memberDetails.toUpperCase(),
                                  style: _DashText.section.copyWith(
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: memberName,
                                  textCapitalization: TextCapitalization.words,
                                  style: appFormValueStyle(context),
                                  decoration: _dashInput(
                                    context,
                                    appStrings.fullName,
                                    Icons.person_outline_rounded,
                                  ),
                                  onChanged: (_) =>
                                      setSheetState(() => memberDirty = true),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                TextField(
                                  controller: memberEmail,
                                  readOnly: true,
                                  style: appFormValueStyle(context),
                                  decoration: _dashInput(
                                    context,
                                    'Email',
                                    Icons.email_outlined,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                TextField(
                                  controller: memberPhone,
                                  keyboardType: TextInputType.phone,
                                  style: appFormValueStyle(context),
                                  decoration: _dashInput(
                                    context,
                                    appStrings.phone,
                                    Icons.phone_outlined,
                                  ),
                                  onChanged: (_) =>
                                      setSheetState(() => memberDirty = true),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                TextField(
                                  controller: memberBirthDate,
                                  readOnly: true,
                                  style: appFormValueStyle(context),
                                  decoration: _dashInput(
                                    context,
                                    appStrings.birthDate,
                                    Icons.calendar_month_outlined,
                                  ),
                                  onTap: () async {
                                    await _pickBirthDate(memberBirthDate);
                                    setSheetState(() => memberDirty = true);
                                  },
                                ),
                                const SizedBox(height: 4),
                                Divider(
                                  color: AppColors.border(context),
                                  height: 24,
                                ),
                                MemberRoleCapabilitySection(
                                  role: selectedRole,
                                  isCoach: memberHasCoachCapability(member),
                                  isUpdatingCoach: updatingCoach,
                                  onRoleSelected: (role) => _updateMemberRole(
                                    member: member,
                                    role: role,
                                    currentSelectedRole: selectedRole,
                                    setSheetState: setSheetState,
                                  ),
                                  onCoachChanged: (isCoach) async {
                                    setSheetState(() => updatingCoach = true);
                                    await _updateMemberCoachCapability(
                                      member: member,
                                      isCoach: isCoach,
                                      setSheetState: setSheetState,
                                    );
                                    if (context.mounted) {
                                      setSheetState(
                                        () => updatingCoach = false,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppFormSubmitButton(
                                  key: const ValueKey(
                                    'member-detail-assign-plan',
                                  ),
                                  label: appStrings.saveChanges,
                                  loading: savingMember,
                                  enabled: memberDirty && !savingMember,
                                  accentColor: AppColors.primary,
                                  onPressed: () async {
                                    setSheetState(() => savingMember = true);
                                    try {
                                      final updated = await Supabase
                                          .instance
                                          .client
                                          .rpc(
                                            'update_gym_member_profile',
                                            params: {
                                              'p_member_id': member['id'],
                                              'p_full_name': memberName.text
                                                  .trim(),
                                              'p_phone': memberPhone.text
                                                  .trim(),
                                              'p_birth_date':
                                                  memberBirthDate.text
                                                      .trim()
                                                      .isEmpty
                                                  ? null
                                                  : memberBirthDate.text.trim(),
                                            },
                                          )
                                          .single();
                                      member.addAll(
                                        Map<String, dynamic>.from(updated),
                                      );
                                      if (!context.mounted) return;
                                      setSheetState(() => memberDirty = false);
                                      setState(() {});
                                    } finally {
                                      if (context.mounted) {
                                        setSheetState(
                                          () => savingMember = false,
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _MemberDetailCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appStrings.membershipTitle.toUpperCase(),
                                  style: _DashText.section.copyWith(
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (membership == null)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceAlt(context),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.border(context),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.card_membership_outlined,
                                            color: AppColors.primary,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 13),
                                        Expanded(
                                          child: Text(
                                            appStrings.noActivePlan,
                                            style: _DashText.body.copyWith(
                                              color: AppColors.textPrimary(
                                                context,
                                              ),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  InkWell(
                                    onTap: () => _openMemberMembershipDetails(
                                      membership,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        14,
                                        16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceAlt(context),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppColors.border(context),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 46,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Icon(
                                              membershipStatus == 'scheduled'
                                                  ? Icons.schedule_rounded
                                                  : Icons
                                                        .check_circle_outline_rounded,
                                              color: AppColors.primary,
                                              size: 23,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  membershipPlanName,
                                                  style: _DashText.title.copyWith(
                                                    color:
                                                        AppColors.textPrimary(
                                                          context,
                                                        ),
                                                    fontSize: 20,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  membershipStatus ==
                                                          'scheduled'
                                                      ? appStrings.scheduled
                                                            .toUpperCase()
                                                      : appStrings.active
                                                            .toUpperCase(),
                                                  style: _DashText.section
                                                      .copyWith(
                                                        color:
                                                            AppColors.primary,
                                                      ),
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  '${_formatDate(membership['starts_at']?.toString())}'
                                                  ' — '
                                                  '${_formatDate(membership['expires_at']?.toString())}',
                                                  style: _DashText.subtle.copyWith(
                                                    color:
                                                        AppColors.textSecondary(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(height: 7),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .confirmation_number_outlined,
                                                      size: 15,
                                                      color:
                                                          AppColors.textSecondary(
                                                            context,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 7),
                                                    Expanded(
                                                      child: Text(
                                                        membershipCreditsLabel,
                                                        style: _DashText.body
                                                            .copyWith(
                                                              color:
                                                                  AppColors.textPrimary(
                                                                    context,
                                                                  ),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    Text(
                                                      appStrings.viewDetails
                                                          .toUpperCase(),
                                                      style: _DashText.section
                                                          .copyWith(
                                                            color: AppColors
                                                                .primary,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    const Icon(
                                                      Icons
                                                          .chevron_right_rounded,
                                                      color: AppColors.primary,
                                                      size: 19,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 18),
                                AppFormSubmitButton(
                                  label: appStrings.assignPlan,
                                  loading: false,
                                  enabled: true,
                                  accentColor: AppColors.primary,
                                  icon: Icons.add_card_rounded,
                                  onPressed: () async {
                                    final assigned = await _openAssignPlan(
                                      member['id'].toString(),
                                    );

                                    if (!assigned || !context.mounted) return;

                                    setSheetState(() {
                                      memberDataFuture = loadMemberData();
                                    });
                                  },
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                MemberMembershipsSection(
                                  memberId: member['id'].toString(),
                                  includeActive: false,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            appStrings.recentClasses.toUpperCase(),
                            style: _DashText.section.copyWith(
                              color: AppColors.textPrimary(context),
                            ),
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
                                  color: AppColors.primary,
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
          _DashboardHeader(gymName: widget.gymName),
          Padding(
            key: const ValueKey('dashboard-section-selector'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenX,
              AppSpacing.md,
              AppSpacing.screenX,
              0,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _DashboardTabChip(
                    label: appStrings.dashboardTitle,
                    selected: _selectedTab == _DashboardTab.overview,
                    onTap: () {
                      setState(() {
                        _selectedTab = _DashboardTab.overview;
                      });
                    },
                  ),
                const SizedBox(width: AppSpacing.xs),
                  _DashboardTabChip(
                    label: appStrings.members,
                    selected: _selectedTab == _DashboardTab.members,
                    onTap: () {
                      setState(() {
                        _selectedTab = _DashboardTab.members;
                      });
                    },
                  ),
                const SizedBox(width: AppSpacing.xs),
                  _DashboardTabChip(
                    label: appStrings.adminMemberships,
                    selected: _selectedTab == _DashboardTab.plans,
                    onTap: () {
                      setState(() {
                        _selectedTab = _DashboardTab.plans;
                      });
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _DashboardTabChip(
                    label: appStrings.analyticsTitle,
                    selected: _selectedTab == _DashboardTab.analytics,
                    onTap: () {
                      setState(() => _selectedTab = _DashboardTab.analytics);
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadDashboardData,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  _selectedTab == _DashboardTab.members ? 16 : 24,
                  24,
                  _selectedTab == _DashboardTab.members ? 16 : 24,
                  28,
                ),
                children: [
                  if (_selectedTab == _DashboardTab.overview) ...[
                    if (_loadingMembers)
                      const AppCenteredLoadingIndicator()
                    else if (_membersError case final error?)
                      AppAsyncState.error(
                        message: error,
                        actionLabel: appStrings.retry,
                        onAction: _loadDashboardData,
                      )
                    else
                      _DashboardOverview(
                        membersCount: _members.length,
                        activeMembersCount: _members
                            .where((m) => m['is_active'] == true)
                            .length,
                        todayBookings: _todayBookings,
                        todayCapacity: _todayCapacity,
                        todayClasses: _todayClasses,
                        todayClassRows: _todayClassRows,
                        joinRequests: _gymJoinRequests,
                        membershipRequests: _membershipRequests,
                        membersWithoutPlan: _membersWithoutPlan,
                        membershipsExpiringSoon: _membershipsExpiringSoon,
                        weeklyBookings: _weeklyBookings,
                        recentActivity: _recentActivity,
                        processingJoinRequestId: _processingGymJoinRequestId,
                        processingJoinAction: _processingGymJoinRequestAction,
                        processingMembershipRequestId:
                            _processingMembershipRequestId,
                        onApproveJoin: _approveGymJoinRequest,
                        onRejectJoin: _rejectGymJoinRequest,
                        onApproveMembership: _approveMembershipRequest,
                        onRejectMembership: _rejectMembershipRequest,
                        onOpenWithoutPlan: () {
                          setState(() {
                            _selectedTab = _DashboardTab.members;
                            _roleFilter = _MemberRoleFilter.withoutPlan;
                            _search.clear();
                          });
                        },
                        onOpenTodayClass: _openCoachClass,
                        onOpenTodayClassBriefing: _openCoachClass,
                        onSendNotification: _openCommunicationSheet,
                      ),
                  ],

                  if (_selectedTab == _DashboardTab.analytics) ...[
                    AnalyticsView(onOpenMember: _openMember),
                  ],

                  if (_selectedTab == _DashboardTab.members) ...[
                    Column(
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
                                    style: AppTypography.sectionTitle(context),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    appStrings.membersCount(_members.length),
                                    style: AppTypography.bodySecondary(context),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 142,
                              height: AppSizes.fieldHeight,
                              child: FilledButton(
                                onPressed: _openInviteMemberSheet,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.input,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.add_rounded,
                                      size: 19,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Flexible(
                                      child: Text(
                                        appStrings.inviteAthlete.toUpperCase(),
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        style: AppTypography.buttonLabel(
                                          context,
                                        ).copyWith(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: AppTypography.body(context),
                          decoration: AppControlStyles.input(
                            context,
                            hintText: appStrings.searchMembers,
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              MemberFilterChip(
                                label: appStrings.membersAllFilter(
                                  _members.length,
                                ),
                                selected: _roleFilter == _MemberRoleFilter.all,
                                onTap: () {
                                  setState(() {
                                    _roleFilter = _MemberRoleFilter.all;
                                  });
                                },
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              MemberFilterChip(
                                label: appStrings.membersWithoutPlanCount(
                                  _membersWithoutPlan.length,
                                ),
                                selected:
                                    _roleFilter ==
                                    _MemberRoleFilter.withoutPlan,
                                onTap: () {
                                  setState(() {
                                    _roleFilter = _MemberRoleFilter.withoutPlan;
                                  });
                                },
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              MemberFilterChip(
                                label: appStrings.membersAthletesFilter(
                                  _athletesCount,
                                ),
                                selected:
                                    _roleFilter == _MemberRoleFilter.athlete,
                                onTap: () {
                                  setState(() {
                                    _roleFilter = _MemberRoleFilter.athlete;
                                  });
                                },
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              MemberFilterChip(
                                label: appStrings.membersCoachesFilter(
                                  _coachesCount,
                                ),
                                selected:
                                    _roleFilter == _MemberRoleFilter.coach,
                                onTap: () {
                                  setState(() {
                                    _roleFilter = _MemberRoleFilter.coach;
                                  });
                                },
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              MemberFilterChip(
                                label: appStrings.membersAdminsFilter(
                                  _adminsCount,
                                ),
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

                        const SizedBox(height: AppSpacing.sm),

                        if (_loadingMembers)
                          const AppCenteredLoadingIndicator()
                        else if (_membersError case final error?)
                          AppAsyncState.error(
                            message: error,
                            actionLabel: appStrings.retry,
                            onAction: _loadMembers,
                          )
                        else if (members.isEmpty)
                          AppAsyncState.empty(
                            message: appStrings.noMembersFound,
                          )
                        else
                          ...members.map(
                            (member) => MemberListRow(
                              member: member,
                              onTap: () => _openMember(member),
                              onMore: () => _openMemberActionsSheet(
                                context: context,
                                active: member['is_active'] == true,
                                isPending:
                                    member['invitation_status'] == 'pending',
                                isDisabled:
                                    member['invitation_status'] == 'disabled',
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
                          ),
                      ],
                    ),
                  ],

                  if (_selectedTab == _DashboardTab.plans) ...[
                    _MembershipOverview(
                      activeMemberships: _activeMembershipMembers.length,
                      membersWithoutPlan: _membersWithoutPlan.length,
                      expiringSoon: _membershipsExpiringSoon.length,
                      mostUsedPlan: _mostUsedPlanName,
                      onManagePlans: _openPlans,
                      requests: _membershipRequests,
                      processingRequestId: _processingMembershipRequestId,
                      onApproveRequest: _approveMembershipRequest,
                      onRejectRequest: _rejectMembershipRequest,
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

class _MembershipOverview extends StatelessWidget {
  const _MembershipOverview({
    required this.activeMemberships,
    required this.membersWithoutPlan,
    required this.expiringSoon,
    required this.mostUsedPlan,
    required this.onManagePlans,
    required this.requests,
    required this.processingRequestId,
    required this.onApproveRequest,
    required this.onRejectRequest,
  });

  final int activeMemberships;
  final int membersWithoutPlan;
  final int expiringSoon;
  final String mostUsedPlan;
  final VoidCallback onManagePlans;
  final List<Map<String, dynamic>> requests;
  final String? processingRequestId;
  final Future<void> Function(Map<String, dynamic>) onApproveRequest;
  final Future<void> Function(Map<String, dynamic>) onRejectRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('membership-overview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appStrings.membershipTitle.toUpperCase(),
                    style: AppTypography.sectionTitle(context),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    appStrings.manageMembershipsDescription,
                    style: AppTypography.bodySecondary(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 178,
              child: AppFormSubmitButton(
                key: const ValueKey('membership-manage-plans'),
                label: appStrings.managePlans,
                loading: false,
                enabled: true,
                onPressed: onManagePlans,
                accentColor: AppColors.primary,
                icon: Icons.add_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: appStrings.activeMemberships,
                value: '$activeMemberships',
                icon: Icons.card_membership_outlined,
              ),
            ),
            Expanded(
              child: _MetricCard(
                label: appStrings.membersWithoutPlan,
                value: '$membersWithoutPlan',
                icon: Icons.person_off_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _MetricCard(
          label: appStrings.expiringSoon,
          value: '$expiringSoon',
          icon: Icons.event_busy_outlined,
        ),
        const SizedBox(height: AppSpacing.lg),
        _MembershipInsightRow(
          icon: Icons.emoji_events_outlined,
          label: appStrings.mostUsedPlan,
          value: mostUsedPlan,
        ),
        if (requests.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            appStrings.membershipRequests.toUpperCase(),
            style: AppTypography.sectionTitle(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...requests.map((request) {
            final processing = processingRequestId == request['id']?.toString();
            final planName =
                request['plan_name']?.toString() ?? appStrings.plan;
            return _ActionRequestRow(
              name: request['member_name']?.toString() ?? appStrings.member,
              subtitle: [
                planName,
                adminMembershipRequestPriceLabel(request),
                appStrings.inPersonPayment,
              ].where((value) => value.isNotEmpty).join(' · '),
              icon: Icons.card_membership_outlined,
              approveLabel: appStrings.confirmPaymentAndActivate,
              isProcessing: processing,
              isApproveProcessing: processing,
              isRejectProcessing: processing,
              disabled: processing,
              onApprove: () => onApproveRequest(request),
              onReject: () => onRejectRequest(request),
            );
          }),
        ],
      ],
    );
  }
}

@visibleForTesting
Widget buildMembershipOverviewForTest({
  List<Map<String, dynamic>> requests = const [],
}) {
  return _MembershipOverview(
    activeMemberships: 12,
    membersWithoutPlan: 3,
    expiringSoon: 2,
    mostUsedPlan: 'Beach',
    onManagePlans: () {},
    requests: requests,
    processingRequestId: null,
    onApproveRequest: (_) async {},
    onRejectRequest: (_) async {},
  );
}

@visibleForTesting
Widget buildMembershipTabCompositionForTest() {
  return Builder(
    builder: (context) => Scaffold(
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          buildDashboardHeaderForTest(unreadNotifications: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.dashboardTitle,
                    selected: false,
                    onTap: () {},
                  ),
                ),
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.members,
                    selected: false,
                    onTap: () {},
                  ),
                ),
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.adminMemberships,
                    selected: true,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [buildMembershipOverviewForTest()],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MembershipInsightRow extends StatelessWidget {
  const _MembershipInsightRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: AppSizes.minimumTouchTarget),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTypography.helper(context),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
      return AppAdminActionSheet(
        accentColor: AppColors.primary,
        onClose: () => Navigator.pop(sheetContext),
        actions: [
          if (!isDisabled)
            AppAdminAction(
              icon: Icons.card_membership_outlined,
              label: appStrings.assignPlan,
              onTap: () async {
                await onAssignPlan();
              },
            ),
          AppAdminAction(
            icon: active
                ? Icons.person_off_outlined
                : Icons.person_add_alt_1_outlined,
            label: active
                ? appStrings.deactivateMember
                : appStrings.activateMember,
            destructive: active,
            onTap: () async {
              await onToggleActive();
            },
          ),
          if (isPending)
            AppAdminAction(
              icon: Icons.mail_outline_rounded,
              label: appStrings.resendInvitation,
              onTap: () async {
                await onResendInvitation();
              },
            ),
          if (isPending)
            AppAdminAction(
              icon: Icons.delete_outline_rounded,
              label: appStrings.deleteInvitation,
              destructive: true,
              onTap: () async {
                await onDeletePendingMember();
              },
            ),
        ],
      );
    },
  );
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
        color: AppColors.surfaceAlt(context),
        child: hasAvatar
            ? Image.network(
                avatarUrl!,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
              )
            : Text(
                name.trim().isEmpty ? 'A' : name.trim()[0].toUpperCase(),
                style: AppTypography.itemTitle(context).copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
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
) => appFormInput(
  context,
  icon: icon,
  accentColor: AppColors.primary,
  hintText: hint,
);

InputDecoration _dashInput(BuildContext context, String hint, IconData icon) =>
    appFormInput(
      context,
      icon: icon,
      accentColor: AppColors.primary,
      hintText: hint,
    );

class _DashText {
  const _DashText._();

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: -0.3,
    height: 1.0,
  );

  static const TextStyle section = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.8,
    height: 1.0,
  );

  static const TextStyle body = TextStyle(
    color: Color(0xFFE5E7EB),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static const TextStyle subtle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Color(0xFF8F96A3),
    letterSpacing: 0.3,
    height: 1.0,
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.gymName});

  final String? gymName;

  @override
  Widget build(BuildContext context) => AppPrimaryGymHeader(gymName: gymName);
}

@visibleForTesting
Widget buildDashboardHeaderForTest({
  String? gymName,
  int unreadNotifications = 0,
  VoidCallback? onManagePlans,
  VoidCallback? onOpenNotifications,
}) {
  return _DashboardHeader(gymName: gymName);
}

@visibleForTesting
Widget buildDashboardCompositionForTest() {
  return Builder(
    builder: (context) => Scaffold(
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          buildDashboardHeaderForTest(gymName: 'Athlete 615'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.dashboardTitle,
                    selected: true,
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.members,
                    selected: false,
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _DashboardTabChip(
                    label: appStrings.adminMemberships,
                    selected: false,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              0,
            ),
            child: SizedBox(
              width: double.infinity,
              child: _DashboardTabChip(
                label: appStrings.analyticsTitle,
                selected: false,
                onTap: () {},
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              children: [buildDashboardOverviewForTest()],
            ),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) =>
      AppSectionChip(label: label, selected: selected, onTap: onTap);
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({
    required this.membersCount,
    required this.activeMembersCount,
    required this.todayBookings,
    required this.todayCapacity,
    required this.todayClasses,
    required this.todayClassRows,
    required this.joinRequests,
    required this.membershipRequests,
    required this.membersWithoutPlan,
    required this.membershipsExpiringSoon,
    required this.weeklyBookings,
    required this.recentActivity,
    required this.processingJoinRequestId,
    required this.processingJoinAction,
    required this.processingMembershipRequestId,
    required this.onApproveJoin,
    required this.onRejectJoin,
    required this.onApproveMembership,
    required this.onRejectMembership,
    required this.onOpenWithoutPlan,
    required this.onOpenTodayClass,
    required this.onOpenTodayClassBriefing,
    required this.onSendNotification,
  });

  final int membersCount;
  final int activeMembersCount;
  final int todayBookings;
  final int todayCapacity;
  final int todayClasses;
  final List<Map<String, dynamic>> todayClassRows;
  final List<Map<String, dynamic>> joinRequests;
  final List<Map<String, dynamic>> membershipRequests;
  final List<Map<String, dynamic>> membersWithoutPlan;
  final List<Map<String, dynamic>> membershipsExpiringSoon;
  final List<int> weeklyBookings;
  final List<Map<String, dynamic>> recentActivity;
  final String? processingJoinRequestId;
  final String? processingJoinAction;
  final String? processingMembershipRequestId;
  final Future<void> Function(Map<String, dynamic>) onApproveJoin;
  final Future<void> Function(Map<String, dynamic>) onRejectJoin;
  final Future<void> Function(Map<String, dynamic>) onApproveMembership;
  final Future<void> Function(Map<String, dynamic>) onRejectMembership;
  final VoidCallback onOpenWithoutPlan;
  final Future<void> Function(Map<String, dynamic>) onOpenTodayClass;
  final Future<void> Function(Map<String, dynamic>) onOpenTodayClassBriefing;
  final VoidCallback onSendNotification;

  @override
  Widget build(BuildContext context) {
    final occupancy = todayCapacity == 0
        ? '0%'
        : '${((todayBookings / todayCapacity) * 100).round()}%';
    final hasAttention =
        joinRequests.isNotEmpty ||
        membershipRequests.isNotEmpty ||
        membersWithoutPlan.isNotEmpty ||
        membershipsExpiringSoon.isNotEmpty;

    return Column(
      key: const ValueKey('dashboard-overview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appStrings.dashboardToday.toUpperCase(),
          style: AppTypography.sectionTitle(context),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          appStrings.dashboardSummary,
          style: AppTypography.bodySecondary(context),
        ),
        const SizedBox(height: AppSpacing.md),
        if (hasAttention) ...[
          _ActionRequiredCard(
            joinRequests: joinRequests,
            membershipRequests: membershipRequests,
            membersWithoutPlan: membersWithoutPlan,
            membershipsExpiringSoon: membershipsExpiringSoon,
            processingJoinRequestId: processingJoinRequestId,
            processingJoinAction: processingJoinAction,
            processingMembershipRequestId: processingMembershipRequestId,
            onApproveJoin: onApproveJoin,
            onRejectJoin: onRejectJoin,
            onApproveMembership: onApproveMembership,
            onRejectMembership: onRejectMembership,
            onOpenWithoutPlan: onOpenWithoutPlan,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        LayoutBuilder(
          key: const ValueKey('dashboard-kpis'),
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _MetricCard(
                    label: appStrings.members,
                    value: '$membersCount',
                    icon: Icons.groups_outlined,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _MetricCard(
                    label: appStrings.active,
                    value: '$activeMembersCount',
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _MetricCard(
                    label: appStrings.occupancyToday,
                    value: occupancy,
                    icon: Icons.pie_chart_outline_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _TodayClassesSummary(
          classes: todayClasses,
          bookings: todayBookings,
          capacity: todayCapacity,
          classRows: todayClassRows,
          onOpenClass: onOpenTodayClass,
          onOpenBriefing: onOpenTodayClassBriefing,
        ),
        const SizedBox(height: AppSpacing.lg),
        _WeeklyBookingsCard(bookings: weeklyBookings),
        const SizedBox(height: AppSpacing.lg),
        _RecentActivityCard(activity: recentActivity),
        const SizedBox(height: AppSpacing.lg),
        _CommunicationCard(onSendNotification: onSendNotification),
      ],
    );
  }
}

@visibleForTesting
Widget buildDashboardOverviewForTest({
  int membersCount = 26,
  int activeMembersCount = 24,
  int todayBookings = 8,
  int todayCapacity = 12,
  int todayClasses = 4,
  List<Map<String, dynamic>>? todayClassRows,
  Future<void> Function(Map<String, dynamic>)? onOpenTodayClass,
  Future<void> Function(Map<String, dynamic>)? onOpenTodayClassBriefing,
}) {
  Future<void> noAction(Map<String, dynamic> _) async {}

  return _DashboardOverview(
    membersCount: membersCount,
    activeMembersCount: activeMembersCount,
    todayBookings: todayBookings,
    todayCapacity: todayCapacity,
    todayClasses: todayClasses,
    todayClassRows:
        todayClassRows ??
        const [
          {
            'id': 'class-1',
            'title': 'WOD',
            'starts_at': '2026-08-14T18:30:00Z',
            'capacity': 10,
            'booking_rows': [
              {'id': 'booking-1', 'user_id': 'member-1'},
              {'id': 'booking-2', 'user_id': 'member-2'},
            ],
            'waitlist_rows': [
              {'user_id': 'member-3'},
            ],
            'programs': {'name': 'CrossFit'},
            'coach': {'full_name': 'Coach Alex'},
          },
        ],
    joinRequests: const [
      {'id': 'request-1', 'member_name': 'Alex Member'},
    ],
    membershipRequests: const [],
    membersWithoutPlan: const [
      {'id': 'member-1', 'full_name': 'Sam Athlete'},
    ],
    membershipsExpiringSoon: const [
      {'id': 'member-2', 'full_name': 'Taylor Athlete'},
    ],
    weeklyBookings: const [2, 5, 4, 8, 6, 3, 7],
    recentActivity: const [
      {
        'member_name': 'Alex Member',
        'status': 'booked',
        'classes': {
          'title': 'Cross Training',
          'starts_at': '2026-08-11T07:30:00Z',
        },
      },
    ],
    processingJoinRequestId: null,
    processingJoinAction: null,
    processingMembershipRequestId: null,
    onApproveJoin: noAction,
    onRejectJoin: noAction,
    onApproveMembership: noAction,
    onRejectMembership: noAction,
    onOpenWithoutPlan: () {},
    onOpenTodayClass: onOpenTodayClass ?? noAction,
    onOpenTodayClassBriefing: onOpenTodayClassBriefing ?? noAction,
    onSendNotification: () {},
  );
}

class _ActionRequiredCard extends StatelessWidget {
  const _ActionRequiredCard({
    required this.joinRequests,
    required this.membershipRequests,
    required this.membersWithoutPlan,
    required this.membershipsExpiringSoon,
    required this.processingJoinRequestId,
    required this.processingJoinAction,
    required this.processingMembershipRequestId,
    required this.onApproveJoin,
    required this.onRejectJoin,
    required this.onApproveMembership,
    required this.onRejectMembership,
    required this.onOpenWithoutPlan,
  });

  final List<Map<String, dynamic>> joinRequests;
  final List<Map<String, dynamic>> membershipRequests;
  final List<Map<String, dynamic>> membersWithoutPlan;
  final List<Map<String, dynamic>> membershipsExpiringSoon;
  final String? processingJoinRequestId;
  final String? processingJoinAction;
  final String? processingMembershipRequestId;
  final Future<void> Function(Map<String, dynamic> request) onApproveJoin;
  final Future<void> Function(Map<String, dynamic> request) onRejectJoin;
  final Future<void> Function(Map<String, dynamic> request) onApproveMembership;
  final Future<void> Function(Map<String, dynamic> request) onRejectMembership;
  final VoidCallback onOpenWithoutPlan;

  @override
  Widget build(BuildContext context) {
    final pendingRequests = joinRequests.length + membershipRequests.length;
    final total =
        pendingRequests +
        membersWithoutPlan.length +
        membershipsExpiringSoon.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (pendingRequests == 0 &&
              membersWithoutPlan.isNotEmpty &&
              membershipsExpiringSoon.isEmpty) {
            onOpenWithoutPlan();
            return;
          }

          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) {
              return _ActionRequiredSheet(
                joinRequests: joinRequests,
                membershipRequests: membershipRequests,
                membersWithoutPlan: membersWithoutPlan,
                membershipsExpiringSoon: membershipsExpiringSoon,
                onApproveJoin: onApproveJoin,
                onRejectJoin: onRejectJoin,
                onApproveMembership: onApproveMembership,
                onRejectMembership: onRejectMembership,
                onOpenWithoutPlan: onOpenWithoutPlan,
              );
            },
          );
        },
        child: Column(
          key: const ValueKey('dashboard-attention'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appStrings.actionRequired.toUpperCase(),
                    style: AppTypography.sectionTitle(context),
                  ),
                ),
                Text(
                  '$total',
                  style: AppTypography.itemTitle(
                    context,
                  ).copyWith(color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary(context),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (pendingRequests > 0)
              _AttentionRow(
                icon: Icons.person_add_alt_1_outlined,
                label: appStrings.pendingApprovalCount(pendingRequests),
              ),
            if (membersWithoutPlan.isNotEmpty)
              _AttentionRow(
                icon: Icons.card_membership_outlined,
                label: appStrings.membersWithoutPlanCount(
                  membersWithoutPlan.length,
                ),
              ),
            if (membershipsExpiringSoon.isNotEmpty)
              _AttentionRow(
                icon: Icons.event_busy_outlined,
                label: appStrings.membershipsExpiringSoonCount(
                  membershipsExpiringSoon.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.minimumTouchTarget),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.body(context))),
        ],
      ),
    );
  }
}

class _ActionRequiredSheet extends StatelessWidget {
  const _ActionRequiredSheet({
    required this.joinRequests,
    required this.membershipRequests,
    required this.membersWithoutPlan,
    required this.membershipsExpiringSoon,
    required this.onApproveJoin,
    required this.onRejectJoin,
    required this.onApproveMembership,
    required this.onRejectMembership,
    required this.onOpenWithoutPlan,
  });

  final List<Map<String, dynamic>> joinRequests;
  final List<Map<String, dynamic>> membershipRequests;
  final List<Map<String, dynamic>> membersWithoutPlan;
  final List<Map<String, dynamic>> membershipsExpiringSoon;
  final Future<void> Function(Map<String, dynamic> request) onApproveJoin;
  final Future<void> Function(Map<String, dynamic> request) onRejectJoin;
  final Future<void> Function(Map<String, dynamic> request) onApproveMembership;
  final Future<void> Function(Map<String, dynamic> request) onRejectMembership;
  final VoidCallback onOpenWithoutPlan;

  String _planLabel(Map<String, dynamic> request) {
    final name = request['plan_name']?.toString() ?? appStrings.plan;
    final credits = request['credits'];

    if (credits == null) return '$name · ${appStrings.unlimited}';
    return '$name · $credits ${appStrings.creditsLower}';
  }

  String _expiryDateLabel(String? raw) {
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return '-';
    return '${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        margin: const EdgeInsets.fromLTRB(16, 72, 16, 16),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          border: Border.all(color: AppColors.border(context), width: 1),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              appStrings.actionRequired.toUpperCase(),
              style: _DashText.section.copyWith(
                color: AppColors.textPrimary(context),
              ),
            ),
            if (joinRequests.isNotEmpty) ...[
              const SizedBox(height: 20),
              _ActionSectionLabel(
                label: appStrings.joinRequests,
                count: joinRequests.length,
              ),
              const SizedBox(height: 10),
              ...joinRequests.map((request) {
                final email = request['member_email']?.toString().trim() ?? '';
                final createdAt = DateTime.tryParse(
                  request['created_at']?.toString() ?? '',
                )?.toLocal();
                final dateLabel = createdAt == null
                    ? ''
                    : DateFormat.yMMMd(
                        Localizations.localeOf(context).languageCode,
                      ).format(createdAt);
                return _ActionRequestRow(
                  name: request['member_name']?.toString() ?? appStrings.member,
                  subtitle: [
                    if (email.isNotEmpty) email,
                    if (dateLabel.isNotEmpty) dateLabel,
                  ].join(' · '),
                  avatarUrl: request['member_avatar_url']?.toString(),
                  isProcessing: false,
                  isApproveProcessing: false,
                  isRejectProcessing: false,
                  disabled: false,
                  onApprove: () {
                    Navigator.pop(context);
                    onApproveJoin(request);
                  },
                  onReject: () {
                    Navigator.pop(context);
                    onRejectJoin(request);
                  },
                );
              }),
            ],
            if (membershipRequests.isNotEmpty) ...[
              const SizedBox(height: 20),
              _ActionSectionLabel(
                label: appStrings.membershipRequests,
                count: membershipRequests.length,
              ),
              const SizedBox(height: 10),
              ...membershipRequests.map((request) {
                return _ActionRequestRow(
                  name: request['member_name']?.toString() ?? appStrings.member,
                  subtitle: [
                    _planLabel(request),
                    adminMembershipRequestPriceLabel(request),
                    appStrings.inPersonPayment,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  icon: Icons.card_membership_outlined,
                  approveLabel: appStrings.confirmPaymentAndActivate,
                  isProcessing: false,
                  isApproveProcessing: false,
                  isRejectProcessing: false,
                  disabled: false,
                  onApprove: () {
                    Navigator.pop(context);
                    onApproveMembership(request);
                  },
                  onReject: () {
                    Navigator.pop(context);
                    onRejectMembership(request);
                  },
                );
              }),
            ],
            if (membershipsExpiringSoon.isNotEmpty) ...[
              const SizedBox(height: 20),
              _ActionSectionLabel(
                label: appStrings.membershipsExpiringSoon,
                count: membershipsExpiringSoon.length,
              ),
              const SizedBox(height: 10),
              ...membershipsExpiringSoon.take(3).map((member) {
                final name =
                    member['full_name']?.toString() ??
                    member['email']?.toString() ??
                    appStrings.member;
                final membershipName =
                    member['membership_name']?.toString() ??
                    appStrings.membershipTitle;
                final expiresAt = member['membership_expires_at']?.toString();

                return _ActionInfoRow(
                  icon: Icons.event_busy_outlined,
                  title: name,
                  subtitle:
                      '$membershipName · ${appStrings.expires} ${_expiryDateLabel(expiresAt)}',
                  onTap: () {},
                );
              }),
            ],
            if (membersWithoutPlan.isNotEmpty) ...[
              const SizedBox(height: 20),
              _ActionSectionLabel(
                label: appStrings.membersWithoutPlan,
                count: membersWithoutPlan.length,
              ),
              const SizedBox(height: 10),
              _ActionInfoRow(
                icon: Icons.person_off_outlined,
                title: appStrings.membersWithoutPlanCount(
                  membersWithoutPlan.length,
                ),
                subtitle: appStrings.membersWithoutPlanDescription,
                onTap: () {
                  Navigator.pop(context);
                  onOpenWithoutPlan();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionInfoRow extends StatelessWidget {
  const _ActionInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(icon, color: AppColors.primary, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _DashText.body.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: _DashText.subtle),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionSectionLabel extends StatelessWidget {
  const _ActionSectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: _DashText.subtle.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Text(
          '$count',
          style: _DashText.subtle.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ActionRequestRow extends StatelessWidget {
  const _ActionRequestRow({
    required this.name,
    required this.subtitle,
    required this.isProcessing,
    required this.isApproveProcessing,
    required this.isRejectProcessing,
    required this.disabled,
    required this.onApprove,
    required this.onReject,
    this.avatarUrl,
    this.icon,
    this.approveLabel,
  });

  final String name;
  final String subtitle;
  final String? avatarUrl;
  final IconData? icon;
  final bool isProcessing;
  final bool isApproveProcessing;
  final bool isRejectProcessing;
  final bool disabled;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String? approveLabel;

  Future<void> _openActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppAdminActionSheet(
        accentColor: AppColors.primary,
        onClose: () => Navigator.pop(sheetContext),
        actions: [
          AppAdminAction(
            icon: Icons.check_circle_outline_rounded,
            label: approveLabel ?? appStrings.approve,
            onTap: onApprove,
          ),
          AppAdminAction(
            icon: Icons.cancel_outlined,
            label: appStrings.reject,
            destructive: true,
            onTap: onReject,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 1),
      ),
      child: Row(
        children: [
          if (icon == null)
            _MemberAvatar(name: name, avatarUrl: avatarUrl)
          else
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(icon, color: AppColors.primary, size: 19),
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
                  style: _DashText.body.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _DashText.subtle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (isProcessing || isApproveProcessing || isRejectProcessing)
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            AppOutlinedAdminButton(
              icon: Icons.edit_outlined,
              tooltip: appStrings.memberOptions,
              onPressed: disabled ? () {} : () => _openActions(context),
              accentColor: AppColors.primary,
            ),
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
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border.all(color: AppColors.border(context), width: 0.8),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
              height: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.helper(context).copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayClassesSummary extends StatelessWidget {
  const _TodayClassesSummary({
    required this.classes,
    required this.bookings,
    required this.capacity,
    required this.classRows,
    required this.onOpenClass,
    required this.onOpenBriefing,
  });

  final int classes;
  final int bookings;
  final int capacity;
  final List<Map<String, dynamic>> classRows;
  final Future<void> Function(Map<String, dynamic>) onOpenClass;
  final Future<void> Function(Map<String, dynamic>) onOpenBriefing;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('dashboard-today-classes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appStrings.todayClasses.toUpperCase(),
          style: AppTypography.sectionTitle(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.minimumTouchTarget,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border(context), width: 0.8),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  '$classes',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.classesToday,
                      style: AppTypography.body(context),
                    ),
                    Text(
                      appStrings.bookingsOfCapacity(bookings, capacity),
                      style: AppTypography.helper(context),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.fitness_center_rounded,
                color: AppColors.primary,
                size: 19,
              ),
            ],
          ),
        ),
        if (classRows.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            appStrings.pick(
              'There are no classes scheduled today.',
              'No hay clases programadas hoy.',
            ),
            style: AppTypography.bodySecondary(context),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.xs),
          ...classRows.map((klass) {
            final rawProgram = klass['programs'];
            final program = rawProgram is Map
                ? rawProgram['name']?.toString().trim()
                : null;
            final startsAt = DateTime.tryParse(
              klass['starts_at']?.toString() ?? '',
            )?.toLocal();
            final coach = klass['coach'];
            final coachName = coach is Map
                ? coach['full_name']?.toString().trim()
                : null;
            final bookingCount = (klass['booking_rows'] as List?)?.length ?? 0;
            final waitlistCount =
                (klass['waitlist_rows'] as List?)?.length ?? 0;
            final capacity = klass['capacity'] as int? ?? 0;
            final occupancy = bookingOccupancy(
              bookedCount: bookingCount,
              capacity: capacity,
            );
            final occupancyLabel = switch (occupancy) {
              BookingOccupancy.available => appStrings.bookingAvailable,
              BookingOccupancy.almostFull => appStrings.bookingAlmostFull,
              BookingOccupancy.full => appStrings.bookingFull,
            };
            final available = capacity > 0
                ? (capacity - bookingCount).clamp(0, capacity)
                : null;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onOpenClass(klass),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.minimumTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.border(context),
                        width: .7,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          startsAt == null
                              ? '—'
                              : DateFormat('HH:mm').format(startsAt),
                          style: AppTypography.body(context),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (program?.isNotEmpty == true)
                              Text(
                                program!.toUpperCase(),
                                key: ValueKey('today-class-program-$program'),
                                style: AppTypography.sectionTitle(context),
                              ),
                            Text(
                              klass['title']?.toString() ??
                                  appStrings.classFallback,
                              style: AppTypography.bodySecondary(context),
                            ),
                            if (coachName?.isNotEmpty == true)
                              Text(
                                coachName!,
                                style: AppTypography.helper(context),
                              ),
                            const SizedBox(height: AppSpacing.xxs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xxs,
                              children: [
                                Text(
                                  capacity > 0
                                      ? '$occupancyLabel · $bookingCount/$capacity'
                                      : occupancyLabel,
                                  key: ValueKey(
                                    'today-class-occupancy-${klass['id']}',
                                  ),
                                  style: AppTypography.helper(context).copyWith(
                                    color: occupancy == BookingOccupancy.full
                                        ? AppColors.danger
                                        : AppColors.textSecondary(context),
                                  ),
                                ),
                                if (available != null && available > 0)
                                  Text(
                                    appStrings.classPlacesAvailable(available),
                                    style: AppTypography.helper(context),
                                  ),
                                if (waitlistCount > 0)
                                  Text(
                                    '${appStrings.waitlist} · $waitlistCount',
                                    style: AppTypography.helper(context),
                                  ),
                              ],
                            ),
                            if (bookingCount > 0 || waitlistCount > 0)
                              TextButton(
                                key: ValueKey(
                                  'today-class-briefing-${klass['id']}',
                                ),
                                onPressed: () => onOpenBriefing(klass),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  appStrings.viewReserved(bookingCount),
                                  style: AppTypography.buttonLabel(
                                    context,
                                  ).copyWith(color: AppColors.primary),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _WeeklyBookingsCard extends StatelessWidget {
  const _WeeklyBookingsCard({required this.bookings});

  final List<int> bookings;

  List<String> _dayLabels() {
    final today = DateTime.now();
    return List.generate(7, (index) {
      final date = today.subtract(Duration(days: 6 - index));
      return appStrings.weekdayInitials[date.weekday - 1];
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = bookings.isEmpty
        ? 0
        : bookings.reduce(
            (value, element) => value > element ? value : element,
          );
    final total = bookings.fold<int>(0, (sum, value) => sum + value);
    final hasBookings = maxValue > 0;
    final labels = _dayLabels();

    return Container(
      key: const ValueKey('dashboard-analytics'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.border(context), width: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  appStrings.weeklyBookings.toUpperCase(),
                  style: _DashText.section,
                ),
              ),
              if (hasBookings)
                Text(
                  appStrings.weeklyBookingsTotal(total),
                  style: _DashText.subtle.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!hasBookings)
            _DashboardEmptyState(
              icon: Icons.bar_chart_rounded,
              message: appStrings.noBookingsYet,
            )
          else
            SizedBox(
              height: 106,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (index) {
                  final value = index < bookings.length ? bookings[index] : 0;
                  final height = 18.0 + (value / maxValue) * 54.0;
                  final highlighted = value == maxValue && maxValue > 0;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '$value',
                            style: _DashText.subtle.copyWith(
                              color: highlighted
                                  ? AppColors.primary
                                  : AppColors.textSecondary(context),
                              fontWeight: highlighted
                                  ? FontWeight.w600
                                  : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: 10,
                                height: height,
                                decoration: BoxDecoration(
                                  color: highlighted
                                      ? AppColors.primary
                                      : AppColors.surfaceAlt(context),
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.xxs,
                                  ),
                                  border: Border.all(
                                    color: highlighted
                                        ? AppColors.primary
                                        : AppColors.border(context),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labels[index],
                            style: _DashText.subtle.copyWith(
                              color: AppColors.textSecondary(context),
                              fontWeight: FontWeight.w600,
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

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary(context), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: _DashText.subtle)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appStrings.communicationTitle.toUpperCase(),
          style: AppTypography.sectionTitle(context),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          appStrings.communicationSubtitle,
          style: AppTypography.bodySecondary(context),
        ),
        const SizedBox(height: AppSpacing.md),
        AppFormSubmitButton(
          label: appStrings.sendCommunication,
          loading: false,
          enabled: true,
          onPressed: onSendNotification,
          accentColor: AppColors.primary,
          icon: Icons.campaign_outlined,
        ),
      ],
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
    return appFormInput(
      context,
      icon: label == appStrings.notificationTitleLabel
          ? Icons.title_rounded
          : Icons.notes_rounded,
      accentColor: AppColors.primary,
      hintText: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Material(
        color: AppColors.surface(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              AppFormHeader(
                title: appStrings.sendCommunication,
                onClose: Navigator.of(context).pop,
                accentColor: AppColors.primary,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenX,
                    AppSpacing.md,
                    AppSpacing.screenX,
                    AppSpacing.lg,
                  ),
                  children: [
                    AppFormSectionLabel(
                      label: appStrings.notificationTitleLabel.toUpperCase(),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      controller: _title,
                      style: appFormValueStyle(context),
                      decoration: _decoration(
                        context,
                        appStrings.notificationTitleLabel,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppFormSectionLabel(
                      label: appStrings.notificationMessageLabel.toUpperCase(),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      controller: _message,
                      minLines: 6,
                      maxLines: 10,
                      style: appFormValueStyle(context),
                      decoration: _decoration(
                        context,
                        appStrings.notificationMessageLabel,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      appStrings.notificationRecipientsLabel.toUpperCase(),
                      style: AppTypography.sectionTitle(context),
                    ),
                    const SizedBox(height: AppSpacing.xs),
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
                              selectedColor: AppColors.primary.withValues(
                                alpha: 0.12,
                              ),
                              backgroundColor: AppColors.surfaceAlt(context),
                              side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.border(context),
                              ),
                              labelStyle: _DashText.body.copyWith(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.textPrimary(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenX,
                  AppSpacing.sm,
                  AppSpacing.screenX,
                  AppSpacing.md,
                ),
                child: AppFormSubmitButton(
                  label: appStrings.sendCommunication,
                  loading: _sending,
                  enabled: !_sending,
                  onPressed: _sendNotification,
                  accentColor: AppColors.primary,
                  icon: Icons.send_outlined,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildAdminCommunicationSheetForTest() =>
    const FractionallySizedBox(heightFactor: .9, child: _CommunicationSheet());

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.activity});

  final List<Map<String, dynamic>> activity;

  String _memberName(Map<String, dynamic> row) {
    return row['member_name']?.toString().trim().isNotEmpty == true
        ? row['member_name'].toString()
        : appStrings.member;
  }

  String _classTitle(Map<String, dynamic> row) {
    final klass = row['classes'];
    return klass is Map
        ? klass['title']?.toString() ?? appStrings.classFallback
        : appStrings.classFallback;
  }

  String _actionLabel(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';

    if (status == 'attended') return appStrings.attended;
    if (status == 'no_show') return appStrings.missed;
    return appStrings.booked;
  }

  IconData _statusIcon(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';

    if (status == 'attended') return Icons.check_rounded;
    if (status == 'no_show') return Icons.close_rounded;
    return Icons.event_available_rounded;
  }

  String _classTimeLabel(Map<String, dynamic> row) {
    final klass = row['classes'];
    final startsAt = klass is Map ? klass['starts_at']?.toString() : null;
    final date = DateTime.tryParse(startsAt ?? '')?.toLocal();

    if (date == null) return '';

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.day}/${date.month}\n$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('dashboard-activity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appStrings.recentActivity.toUpperCase(),
          style: AppTypography.sectionTitle(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (activity.isEmpty)
          AppAsyncState.empty(
            icon: Icons.history_rounded,
            message: appStrings.noRecentActivity,
          )
        else
          ...activity.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final isLast = index == activity.length - 1;

            return Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: AppColors.border(context),
                          width: 0.8,
                        ),
                      ),
              ),
              child: Row(
                children: [
                  Icon(_statusIcon(row), size: 18, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _memberName(row),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${_actionLabel(row)} · ${_classTitle(row)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.helper(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _classTimeLabel(row),
                    textAlign: TextAlign.right,
                    style: AppTypography.helper(context),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _MemberOverviewCard extends StatelessWidget {
  const _MemberOverviewCard({
    required this.attendedThisMonth,
    required this.noShowsThisMonth,
    required this.lastAttendance,
    required this.totalAttended,
  });

  final int attendedThisMonth;
  final int noShowsThisMonth;
  final String lastAttendance;
  final int totalAttended;

  @override
  Widget build(BuildContext context) {
    return _MemberDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.memberOverview.toUpperCase(),
            style: _DashText.section.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MemberStatTile(
                  label: appStrings.attendedThisMonth,
                  value: '$attendedThisMonth',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MemberStatTile(
                  label: appStrings.noShowsThisMonth,
                  value: '$noShowsThisMonth',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MemberStatTile(
                  label: appStrings.lastAttendance,
                  value: lastAttendance,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MemberStatTile(
                  label: appStrings.totalAttended,
                  value: '$totalAttended',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberStatTile extends StatelessWidget {
  const _MemberStatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _DashText.subtle),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _DashText.title.copyWith(
              color: AppColors.textPrimary(context),
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
          Text(
            appStrings.milestone.toUpperCase(),
            style: _DashText.section.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$attendedCount / $target ${appStrings.classesAttended}',
                  style: _DashText.title.copyWith(
                    color: AppColors.textPrimary(context),
                  ),
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
              backgroundColor: AppColors.surfaceAlt(context),
              color: AppColors.primary,
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
      color: selected ? AppColors.primary : AppColors.surfaceAlt(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: AppTypography.helper(context).copyWith(
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : AppColors.textSecondary(context),
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
          color: AppColors.surfaceAlt(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _DashText.title.copyWith(
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_formattedSubtitle, style: _DashText.subtle),
                ],
              ),
            ),
            if (marker.isNotEmpty)
              Text(
                marker,
                style: _DashText.title.copyWith(
                  color: AppColors.textPrimary(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
