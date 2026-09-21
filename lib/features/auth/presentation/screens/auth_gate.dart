import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/deep_link_service.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../data/app_auth_coordinator.dart';
import '../../data/session_access_revalidator.dart';

bool shouldAuthGateRedirect(String currentPath) => currentPath == '/';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _redirecting = false;

  @override
  void initState() {
    super.initState();
    appAuthCoordinator.addListener(_onAuthStateChanged);
    Future.microtask(_redirect);
  }

  @override
  void dispose() {
    appAuthCoordinator.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() => _redirect();

  Future<void> _redirect() async {
    if (!mounted || _redirecting || appAuthCoordinator.isTransitioning) return;
    if (appAuthCoordinator.requiresPasswordRecovery) {
      context.go('/reset-password');
      return;
    }
    final revision = appAuthCoordinator.revision;
    _redirecting = true;

    final currentPath = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    if (!shouldAuthGateRedirect(currentPath)) {
      _redirecting = false;
      return;
    }

    if (appAuthCoordinator.state == AppAuthState.definitivelyUnauthenticated) {
      _redirecting = false;
      context.go('/login');
      return;
    }

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      _redirecting = false;
      return;
    }

    appAuthCoordinator.beginRefresh();
    final result = await SessionAccessRevalidator(
      SupabaseSessionAccessDataSource(client),
    ).validate(userId: user.id, cachedGymId: null);

    if (!mounted) return;
    if (revision != appAuthCoordinator.revision) {
      _redirecting = false;
      return;
    }

    if (result.state == SessionAccessState.transientFailure) {
      appAuthCoordinator.preserveAfterTransientFailure(
        sessionPresent: client.auth.currentSession != null,
      );
      _redirecting = false;
      return;
    }
    if (result.state == SessionAccessState.accountInvalid) {
      appAuthCoordinator.markDefinitelyUnauthenticated(
        reason: 'auth_gate_revalidation_failed',
      );
    } else {
      appAuthCoordinator.markAuthenticated(reason: 'auth_gate_revalidated');
    }
    recordSessionAccessResult(result);
    final pending = pendingDeepLinkDestination.take();
    context.go(result.destination ?? pending ?? '/app');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: AppCenteredLoadingIndicator());
  }
}
