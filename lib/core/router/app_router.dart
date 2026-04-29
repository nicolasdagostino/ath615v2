import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/screens/auth_gate.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/home/presentation/screens/app_shell.dart';
import '../../features/owner/presentation/screens/owner_screen.dart';

class AppRouter {
  static final _rootKey = GlobalKey<NavigatorState>();

  static GoRouter get router {
    final authRepo = AuthRepository(Supabase.instance.client);

    return GoRouter(
      navigatorKey: _rootKey,
      initialLocation: '/',
      refreshListenable: _AuthRefresh(authRepo),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const AuthGate()),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/reset-password',
          builder: (context, state) => const ResetPasswordScreen(),
        ),
        GoRoute(
          path: '/owner',
          builder: (context, state) => const OwnerScreen(),
        ),
        GoRoute(path: '/app', builder: (context, state) => const AppShell()),
      ],
    );
  }
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(AuthRepository authRepository) {
    authRepository.authStateChanges.listen((_) => notifyListeners());
  }
}
