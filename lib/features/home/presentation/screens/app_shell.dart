import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../booking/presentation/screens/booking_screen.dart';
import '../../../booking/presentation/screens/coach_briefing_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../notifications/data/notifications_repository.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../workouts/presentation/screens/workouts_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialRoleForTesting,
    this.screenBuilderForTesting,
    this.initialSection,
    this.initialNotificationId,
    this.ownerInspection = false,
    this.initialWorkoutDate,
    this.initialUnreadForTesting = 0,
    this.initialDashboardMemberIdForTesting,
    this.dashboardScreenBuilderForTesting,
  });

  final String? initialSection;
  final String? initialNotificationId;
  final bool ownerInspection;
  final DateTime? initialWorkoutDate;

  @visibleForTesting
  final int initialUnreadForTesting;

  @visibleForTesting
  final String? initialRoleForTesting;

  @visibleForTesting
  final String? initialDashboardMemberIdForTesting;

  @visibleForTesting
  final Widget Function(String? section, String? memberId)?
  dashboardScreenBuilderForTesting;

  @visibleForTesting
  final Widget Function(String section)? screenBuilderForTesting;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  String? _role;
  bool _isCoach = false;
  bool _initialSectionResolved = false;
  String? _gymName;
  String? _dashboardSection;
  String? _dashboardMemberId;
  int _unreadNotifications = 0;
  RealtimeChannel? _notificationsChannel;
  String? _gymLifecycleStatus;
  List<Map<String, dynamic>> _alternativeGyms = const [];

  @override
  void initState() {
    super.initState();
    _dashboardSection = widget.initialSection;
    _dashboardMemberId = widget.initialDashboardMemberIdForTesting;
    _unreadNotifications = widget.initialUnreadForTesting;
    final initialRole = widget.initialRoleForTesting;
    if (initialRole == null) {
      _loadRole();
    } else {
      _role = initialRole;
      _index = initialShellIndexForRole(
        initialRole,
        requestedSection: widget.initialSection,
      );
      _initialSectionResolved = true;
    }
    if (widget.screenBuilderForTesting == null) {
      _loadUnreadNotifications();
      _subscribeToNotifications();
      notificationsInboxEvents.addListener(_loadUnreadNotifications);
    }
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection == 'messages' &&
        (oldWidget.initialSection != widget.initialSection ||
            oldWidget.initialNotificationId != widget.initialNotificationId)) {
      setState(() => _index = 2);
    }
  }

  void _subscribeToNotifications() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _notificationsChannel = Supabase.instance.client
        .channel('shell-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _loadUnreadNotifications(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    notificationsInboxEvents.removeListener(_loadUnreadNotifications);
    final channel = _notificationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _loadRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role, gym_id, is_coach')
        .eq('id', user.id)
        .single();

    Map<String, dynamic>? accessContext;
    try {
      final raw = await Supabase.instance.client.rpc(
        'get_selected_gym_access_context',
      );
      if (raw is Map) accessContext = Map<String, dynamic>.from(raw);
    } catch (_) {}

    final gymId =
        accessContext?['selected_gym_id']?.toString() ??
        profile['gym_id']?.toString();

    String? gymName = accessContext?['selected_gym_name']?.toString();

    if (gymId != null && gymName == null) {
      try {
        final gym = await Supabase.instance.client
            .from('gyms')
            .select('name')
            .eq('id', gymId)
            .maybeSingle();

        gymName = gym?['name']?.toString();
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _role = profile['role'] as String?;
      _isCoach = profile['is_coach'] == true || _role == 'coach';
      _gymName = gymName;
      _gymLifecycleStatus = accessContext?['status']?.toString();
      _alternativeGyms = List<Map<String, dynamic>>.from(
        accessContext?['active_gyms'] as List? ?? const [],
      );
      if (!_initialSectionResolved) {
        _index = initialShellIndexForRole(
          _role,
          requestedSection: widget.initialSection,
        );
        _initialSectionResolved = true;
      }
    });
  }

  Future<void> _loadUnreadNotifications() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final count = await SupabaseNotificationsRepository(
        Supabase.instance.client,
      ).unreadCount();

      if (!mounted) return;
      setState(() => _unreadNotifications = count);
    } catch (_) {
      if (!mounted) return;
      setState(() => _unreadNotifications = 0);
    }
  }

  void _openNotifications() {
    setState(() => _index = 2);
  }

  void _openMembershipRequests() {
    if (_role != 'admin' && _role != 'owner') return;
    setState(() {
      _dashboardSection = 'membership';
      _index = 4;
    });
  }

  void _openAdminMember(String memberId) {
    if (_role != 'admin' && _role != 'owner') return;
    setState(() {
      _dashboardSection = 'members';
      _dashboardMemberId = memberId;
      _index = 4;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_role == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final canSeeDashboard = _role == 'admin' || _role == 'owner';
    final usesCoachBriefing = _isCoach || _role == 'coach';

    if (_gymLifecycleStatus != null && _gymLifecycleStatus != 'active') {
      return _GymLifecycleBlocked(
        status: _gymLifecycleStatus!,
        gymName: _gymName,
        alternatives: _alternativeGyms,
        ownerInspection: widget.ownerInspection && _role == 'owner',
        onSelectGym: (gymId) async {
          await Supabase.instance.client.rpc(
            'select_effective_gym',
            params: {'p_gym_id': gymId},
          );
          await _loadRole();
        },
        onReturnOwner: _returnToOwner,
      );
    }

    final testScreenBuilder = widget.screenBuilderForTesting;
    final screens = testScreenBuilder == null
        ? <Widget>[
            if (usesCoachBriefing)
              CoachBriefingScreen(gymName: _gymName)
            else
              WorkoutsScreen(
                gymName: _gymName,
                unreadNotifications: _unreadNotifications,
                onOpenNotifications: _openNotifications,
                initialDate: widget.initialWorkoutDate,
              ),
            BookingScreen(
              gymName: _gymName,
              unreadNotifications: _unreadNotifications,
              onOpenNotifications: _openNotifications,
              onOpenAdminMember: canSeeDashboard ? _openAdminMember : null,
            ),
            NotificationsScreen(
              key: ValueKey(
                'messages-${widget.initialNotificationId ?? 'inbox'}',
              ),
              initialNotificationId: widget.initialNotificationId,
              gymName: _gymName,
              onNotificationsRead: _loadUnreadNotifications,
              onOpenMembershipRequests: _openMembershipRequests,
            ),
            ProfileScreen(
              gymName: _gymName,
              onGymNameChanged: _loadRole,
              unreadNotifications: _unreadNotifications,
              onOpenNotifications: _openNotifications,
            ),
            if (canSeeDashboard)
              DashboardScreen(
                key: ValueKey(
                  'dashboard-${_dashboardSection ?? 'panel'}-'
                  '${_dashboardMemberId ?? ''}',
                ),
                gymName: _gymName,
                unreadNotifications: _unreadNotifications,
                onOpenNotifications: _openNotifications,
                initialSection: _dashboardSection,
                initialMemberId: _dashboardMemberId,
              ),
          ]
        : <Widget>[
            testScreenBuilder(usesCoachBriefing ? 'briefing' : 'workouts'),
            testScreenBuilder('booking'),
            testScreenBuilder('messages'),
            testScreenBuilder('profile'),
            if (canSeeDashboard)
              widget.dashboardScreenBuilderForTesting?.call(
                    _dashboardSection,
                    _dashboardMemberId,
                  ) ??
                  testScreenBuilder('dashboard'),
          ];

    final navItems = [
      _ShellNavItem(
        icon: Icons.fitness_center_outlined,
        activeIcon: Icons.fitness_center,
        label: usesCoachBriefing
            ? appStrings.pick('Briefing', 'Briefing')
            : appStrings.navWorkout,
      ),
      _ShellNavItem(
        icon: Icons.calendar_month_outlined,
        activeIcon: Icons.calendar_month,
        label: appStrings.navBooking,
      ),
      _ShellNavItem(
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        label: appStrings.navMessages,
        badgeCount: _unreadNotifications,
      ),
      _ShellNavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: appStrings.navProfile,
      ),
      if (canSeeDashboard)
        _ShellNavItem(
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          label: appStrings.navDashboard,
        ),
    ];

    if (_index >= screens.length) {
      _index = 0;
    }

    return Scaffold(
      body: Column(
        children: [
          if (widget.ownerInspection && _role == 'owner')
            Material(
              color: AppColors.primary,
              child: SafeArea(
                bottom: false,
                child: ListTile(
                  dense: true,
                  title: Text(
                    appStrings.pick(
                      'ADMIN INSPECTION MODE',
                      'MODO INSPECCIÓN ADMIN',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _returnToOwner,
                    child: Text(
                      appStrings.pick('RETURN TO OWNER', 'VOLVER A OWNER'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: screens[_index]),
        ],
      ),
      bottomNavigationBar: _ShellBottomNav(
        index: _index,
        items: navItems,
        onSelected: (value) {
          setState(() {
            _index = value;
            if (canSeeDashboard && value == 4) {
              _dashboardSection = null;
              _dashboardMemberId = null;
            }
          });
          if (value == 2 && widget.screenBuilderForTesting == null) {
            _loadUnreadNotifications();
          }
        },
      ),
    );
  }

  Future<void> _returnToOwner() async {
    await Supabase.instance.client.rpc('leave_owner_gym_inspection');
    if (!mounted) return;
    context.go('/owner');
  }
}

class _GymLifecycleBlocked extends StatelessWidget {
  const _GymLifecycleBlocked({
    required this.status,
    required this.gymName,
    required this.alternatives,
    required this.ownerInspection,
    required this.onSelectGym,
    required this.onReturnOwner,
  });
  final String status;
  final String? gymName;
  final List<Map<String, dynamic>> alternatives;
  final bool ownerInspection;
  final ValueChanged<String> onSelectGym;
  final VoidCallback onReturnOwner;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenX),
        children: [
          Icon(
            status == 'archived'
                ? Icons.archive_outlined
                : Icons.pause_circle_outline,
            size: 52,
            color: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            gymName ?? appStrings.appBrand,
            style: AppTypography.itemTitle(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            status == 'archived'
                ? appStrings.pick(
                    'This center is archived and is not available for operational use.',
                    'Este centro está archivado y no está disponible para uso operativo.',
                  )
                : appStrings.pick(
                    'This center is temporarily suspended. Contact the service administrator.',
                    'Este centro está temporalmente suspendido. Contacta con el administrador del servicio.',
                  ),
            style: AppTypography.body(context),
          ),
          if (ownerInspection) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: onReturnOwner,
              child: Text(appStrings.pick('RETURN TO OWNER', 'VOLVER A OWNER')),
            ),
          ],
          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              appStrings.pick('AVAILABLE GYMS', 'GIMNASIOS DISPONIBLES'),
              style: AppTypography.sectionTitle(context),
            ),
            ...alternatives.map(
              (g) => ListTile(
                title: Text(g['name']?.toString() ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onSelectGym(g['id'].toString()),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

@visibleForTesting
Widget buildGymLifecycleBlockedForTesting({
  required String status,
  String? gymName,
  List<Map<String, dynamic>> alternatives = const [],
  bool ownerInspection = false,
  ValueChanged<String>? onSelectGym,
  VoidCallback? onReturnOwner,
}) => _GymLifecycleBlocked(
  status: status,
  gymName: gymName,
  alternatives: alternatives,
  ownerInspection: ownerInspection,
  onSelectGym: onSelectGym ?? (_) {},
  onReturnOwner: onReturnOwner ?? () {},
);

@visibleForTesting
int initialShellIndexForRole(String? role, {String? requestedSection}) {
  if (requestedSection == 'wod') return 0;
  if (requestedSection == 'messages') return 2;
  if (requestedSection == 'membership' &&
      (role == 'admin' || role == 'owner')) {
    return 4;
  }
  return switch (role) {
    'admin' || 'owner' => 4,
    'athlete' => 1,
    _ => 0,
  };
}

class _ShellNavItem {
  const _ShellNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badgeCount;
}

class _ShellBottomNav extends StatelessWidget {
  const _ShellBottomNav({
    required this.index,
    required this.items,
    required this.onSelected,
  });

  final int index;
  final List<_ShellNavItem> items;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border(top: BorderSide(color: AppColors.border(context))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: List.generate(items.length, (i) {
                final selected = index == i;
                final item = items[i];

                return Expanded(
                  child: InkWell(
                    onTap: () => onSelected(i),
                    borderRadius: BorderRadius.circular(AppRadii.input),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 7, bottom: 5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: selected ? 34 : 30,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Badge(
                              isLabelVisible: item.badgeCount > 0,
                              backgroundColor: AppColors.danger,
                              label: Text(
                                item.badgeCount > 99
                                    ? '99+'
                                    : '${item.badgeCount}',
                              ),
                              child: Icon(
                                selected ? item.activeIcon : item.icon,
                                size: 22,
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.textSecondary(context),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.buttonLabel(context).copyWith(
                              fontSize: 10,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
