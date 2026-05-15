import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../booking/presentation/screens/booking_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../explore/presentation/screens/explore_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../workouts/presentation/screens/workouts_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  String? _role;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadUnreadNotifications();
  }

  Future<void> _loadRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role, gym_id')
        .eq('id', user.id)
        .single();

    if (!mounted) return;

    setState(() {
      _role = profile['role'] as String?;
    });
  }

  Future<void> _loadUnreadNotifications() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .isFilter('read_at', null)
          .not('sent_at', 'is', null);

      if (!mounted) return;
      setState(() => _unreadNotifications = List.from(rows).length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _unreadNotifications = 0);
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));

    await _loadUnreadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    if (_role == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFB59B6A)),
        ),
      );
    }

    final canSeeDashboard = _role == 'admin' || _role == 'owner';

    final screens = [
      WorkoutsScreen(
        unreadNotifications: _unreadNotifications,
        onOpenNotifications: _openNotifications,
      ),
      BookingScreen(
        unreadNotifications: _unreadNotifications,
        onOpenNotifications: _openNotifications,
      ),
      ExploreScreen(
        unreadNotifications: _unreadNotifications,
        onOpenNotifications: _openNotifications,
      ),
      ProfileScreen(
        unreadNotifications: _unreadNotifications,
        onOpenNotifications: _openNotifications,
      ),
      if (canSeeDashboard)
        DashboardScreen(
          unreadNotifications: _unreadNotifications,
          onOpenNotifications: _openNotifications,
        ),
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
        icon: Icons.search_outlined,
        activeIcon: Icons.search,
        label: appStrings.navExplore,
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
        onSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _ShellNavItem {
  const _ShellNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDEFF3), width: 0.8)),
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
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
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
                                  ? const Color(0xFFF7F3EA)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Icon(
                              selected ? item.activeIcon : item.icon,
                              size: 22,
                              color: selected
                                  ? const Color(0xFFB59B6A)
                                  : const Color(0xFF8F96A3),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 11.5,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? const Color(0xFF111318)
                                  : const Color(0xFF8F96A3),
                              letterSpacing: 0.1,
                              height: 1.0,
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
