import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../data/session_access_revalidator.dart';

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

    final result = await SessionAccessRevalidator(
      SupabaseSessionAccessDataSource(client),
    ).validate(userId: user.id, cachedGymId: null);

    if (!mounted) return;

    if (result.state == SessionAccessState.transientFailure) return;
    recordSessionAccessResult(result);
    context.go(result.destination ?? '/app');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: AppCenteredLoadingIndicator());
  }
}
