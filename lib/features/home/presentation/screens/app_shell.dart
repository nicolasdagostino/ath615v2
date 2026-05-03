import 'package:flutter/material.dart';
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
  String _gymName = 'Athlete 615';
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

    String gymName = 'Athlete 615';
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final canSeeDashboard = _role == 'admin' || _role == 'owner';

    final screens = [
      const WorkoutsScreen(),
      const BookingScreen(),
      const ExploreScreen(),
      const ProfileScreen(),
      if (canSeeDashboard) const DashboardScreen(),
    ];

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.fitness_center),
        label: 'Workout',
      ),
      const NavigationDestination(
        icon: Icon(Icons.calendar_month),
        label: 'Booking',
      ),
      const NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
      const NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      if (canSeeDashboard)
        const NavigationDestination(
          icon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
    ];

    if (_index >= screens.length) {
      _index = 0;
    }

    return Scaffold(
      appBar: AppBar(
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: destinations,
      ),
    );
  }
}
