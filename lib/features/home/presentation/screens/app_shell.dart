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
  String _gymName = appStrings.defaultGymName;
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

    String gymName = appStrings.defaultGymName;
    final gymId = profile['gym_id'] as String?;

    if (gymId != null) {
      final gym = await Supabase.instance.client
          .from('gyms')
          .select('name')
          .eq('id', gymId)
          .maybeSingle();

      gymName = gym?['name']?.toString() ?? gymName;
    }

    setState(() {
      _role = profile['role'] as String?;
      _gymName = gymName;
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
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFB59B6A))));
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
      if (canSeeDashboard) const DashboardScreen(),
    ];

    final destinations = [
      NavigationDestination(
        icon: Icon(Icons.fitness_center),
        label: appStrings.navWorkout,
      ),
      NavigationDestination(
        icon: Icon(Icons.calendar_month),
        label: appStrings.navBooking,
      ),
      NavigationDestination(
        icon: Icon(Icons.search),
        label: appStrings.navExplore,
      ),
      NavigationDestination(
        icon: Icon(Icons.person),
        label: appStrings.navProfile,
      ),
      if (canSeeDashboard)
        NavigationDestination(
          icon: Icon(Icons.dashboard),
          label: appStrings.navDashboard,
        ),
    ];

    if (_index >= screens.length) {
      _index = 0;
    }

    final hideAppBar = _index == 0 || _index == 1 || _index == 2 || _index == 3;

    return Scaffold(
      appBar: hideAppBar
          ? null
          : AppBar(
              title: Text(_gymName),
              actions: [
                IconButton(
                  icon: Badge(
                    isLabelVisible: _unreadNotifications > 0,
                    label: Text(
                      _unreadNotifications > 99
                          ? '99+'
                          : _unreadNotifications.toString(),
                    ),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  onPressed: _openNotifications,
                ),
              ],
            ),
      body: screens[_index],
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 88,
          backgroundColor: Colors.white,
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return GoogleFonts.barlowCondensed(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? const Color(0xFF111318)
                  : const Color(0xFF8F96A3),
              letterSpacing: 0.1,
              height: 1.0,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 25,
              color: selected
                  ? const Color(0xFF111318)
                  : const Color(0xFF8F96A3),
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: destinations,
        ),
      ),
    );
  }
}
