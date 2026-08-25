import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_centered_loading_indicator.dart';

bool shouldAuthGateRedirect(String currentPath) => currentPath == '/';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_redirect);
  }

  Future<void> _redirect() async {
    await Future<void>.delayed(const Duration(milliseconds: 1800));

    if (!mounted) return;

    final currentPath = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    if (!shouldAuthGateRedirect(currentPath)) return;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      context.go('/login');
      return;
    }

    final profile = await client
        .from('profiles')
        .select('role, gym_id')
        .eq('id', user.id)
        .single();

    if (!mounted) return;

    final role = profile['role']?.toString();
    final gymId = profile['gym_id']?.toString();

    if (role == 'owner') {
      context.go('/owner');
    } else if (gymId == null || gymId.isEmpty) {
      context.go('/join-gym');
    } else {
      context.go('/app');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: AppCenteredLoadingIndicator());
  }
}
