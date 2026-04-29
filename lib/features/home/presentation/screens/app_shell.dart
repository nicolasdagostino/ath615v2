import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../booking/presentation/screens/booking_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../explore/presentation/screens/explore_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../workouts/presentation/screens/workouts_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .single();

    if (!mounted) return;

    setState(() => _role = profile['role'] as String?);
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
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: destinations,
      ),
    );
  }
}
