import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../booking/presentation/screens/booking_screen.dart';
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
    this.initialWorkoutDate,
    this.initialUnreadForTesting = 0,
  });

  final String? initialSection;
  final DateTime? initialWorkoutDate;

  @visibleForTesting
  final int initialUnreadForTesting;

  @visibleForTesting
  final String? initialRoleForTesting;

  @visibleForTesting
  final Widget Function(String section)? screenBuilderForTesting;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  String? _role;
  bool _initialSectionResolved = false;
  String? _gymName;
  String? _dashboardSection;
  String? _dashboardMemberId;
  int _unreadNotifications = 0;
  RealtimeChannel? _notificationsChannel;

  @override
  void initState() {
    super.initState();
    _dashboardSection = widget.initialSection;
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
        .select('role, gym_id')
        .eq('id', user.id)
        .single();

    final gymId = profile['gym_id']?.toString();

    String? gymName;

    if (gymId != null) {
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
      _gymName = gymName;
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
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final canSeeDashboard = _role == 'admin' || _role == 'owner';

    final testScreenBuilder = widget.screenBuilderForTesting;
    final screens = testScreenBuilder == null
        ? <Widget>[
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
            testScreenBuilder('workouts'),
            testScreenBuilder('booking'),
            testScreenBuilder('messages'),
            testScreenBuilder('profile'),
            if (canSeeDashboard) testScreenBuilder('dashboard'),
          ];

    final navItems = [
      _ShellNavItem(
        icon: Icons.fitness_center_outlined,
        activeIcon: Icons.fitness_center,
        label: appStrings.navWorkout,
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
      body: screens[_index],
      bottomNavigationBar: _ShellBottomNav(
        index: _index,
        items: navItems,
        onSelected: (value) {
          setState(() => _index = value);
          if (value == 2 && widget.screenBuilderForTesting == null) {
            _loadUnreadNotifications();
          }
        },
      ),
    );
  }
}

@visibleForTesting
int initialShellIndexForRole(String? role, {String? requestedSection}) {
  if (requestedSection == 'wod') return 0;
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
