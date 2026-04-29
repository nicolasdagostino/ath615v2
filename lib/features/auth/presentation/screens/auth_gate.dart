import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    if (currentPath == '/reset-password') return;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      context.go('/login');
      return;
    }

    final profile = await client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .single();

    if (!mounted) return;

    if (profile['role'] == 'owner') {
      context.go('/owner');
    } else {
      context.go('/app');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
