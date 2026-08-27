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
import '../../features/notifications/presentation/screens/notification_preferences_screen.dart';
import '../../features/notifications/navigation/notification_destination.dart';
import '../../features/owner/presentation/screens/owner_screen.dart';
import '../../features/profile/presentation/screens/account_screen.dart';
import '../../features/profile/presentation/screens/training_screen.dart';
import '../../features/profile/presentation/screens/membership_screen.dart';
import '../../features/profile/presentation/screens/available_memberships_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/profile/presentation/screens/preferences_screen.dart';
import '../../features/profile/presentation/screens/settings_resource_screens.dart';
import '../../features/profile/presentation/screens/gym_settings_screen.dart';
import '../../features/profile/presentation/screens/gym_documents_screen.dart';
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
        GoRoute(
          path: '/app',
          builder: (context, state) => AppShell(
            initialSection: state.uri.queryParameters['section'],
            initialNotificationId: state.uri.queryParameters['notificationId'],
            initialWorkoutDate: parseNotificationDate(
              state.uri.queryParameters['date'],
            ),
          ),
        ),
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
          path: '/preferences',
          builder: (context, state) => const PreferencesScreen(),
        ),
        GoRoute(
          path: '/legal',
          builder: (context, state) =>
              const SettingsResourceScreen(type: SettingsResourceType.legal),
        ),
        GoRoute(
          path: '/documents',
          builder: (context, state) => const GymDocumentsScreen(),
        ),
        GoRoute(
          path: '/gym-documents',
          builder: (context, state) => const GymDocumentsScreen(admin: true),
        ),
        GoRoute(
          path: '/payments',
          builder: (context, state) =>
              const SettingsResourceScreen(type: SettingsResourceType.payments),
        ),
        GoRoute(
          path: '/gym-settings',
          builder: (context, state) => GymSettingsScreen(
            connectAction: parseStripeConnectRouteAction(
              state.uri.queryParameters['stripeConnect'],
            ),
          ),
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
          path: '/notification-preferences',
          builder: (context, state) => const NotificationPreferencesScreen(),
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
