import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/screens/auth_gate.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/sign_up_screen.dart';
import '../../features/home/presentation/screens/app_shell.dart';
import '../../features/onboarding/presentation/screens/join_gym_screen.dart';
import '../../features/onboarding/presentation/screens/scan_gym_qr_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/owner/presentation/screens/owner_screen.dart';
import '../../features/profile/presentation/screens/account_screen.dart';
import '../../features/profile/presentation/screens/training_screen.dart';
import '../../features/profile/presentation/screens/membership_screen.dart';
import '../../features/profile/presentation/screens/available_memberships_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/profile/presentation/screens/gym_settings_screen.dart';
import '../../features/workouts/presentation/screens/workout_detail_screen.dart';

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
          path: '/signup',
          builder: (context, state) => const SignUpScreen(),
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
        GoRoute(
          path: '/join-gym',
          builder: (context, state) => const JoinGymScreen(),
        ),
        GoRoute(
          path: '/scan-gym-qr',
          builder: (context, state) => const ScanGymQrScreen(),
        ),
        GoRoute(
          path: '/account',
          builder: (context, state) => const AccountScreen(),
        ),
        GoRoute(
          path: '/training',
          builder: (context, state) => const TrainingScreen(),
        ),
        GoRoute(
          path: '/records',
          builder: (context, state) => const TrainingScreen(recordsOnly: true),
        ),
        GoRoute(
          path: '/membership',
          builder: (context, state) => const MembershipScreen(),
        ),
        GoRoute(
          path: '/available-memberships/:type',
          builder: (context, state) {
            return AvailableMembershipsScreen(
              type: state.pathParameters['type'] ?? 'subscription',
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/gym-settings',
          builder: (context, state) => const GymSettingsScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) {
            return NotificationsScreen(
              initialNotificationId:
                  state.uri.queryParameters['notificationId'],
            );
          },
        ),
        GoRoute(
          path: '/workout/:id',
          builder: (context, state) {
            final workoutId = state.pathParameters['id'] ?? '';
            return WorkoutDetailScreen(workoutId: workoutId);
          },
        ),
      ],
    );
  }
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(AuthRepository authRepository) {
    authRepository.authStateChanges.listen((_) => notifyListeners());
  }
}
