import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/session_access_revalidator.dart';
import '../../features/auth/data/password_recovery_controller.dart';
import '../../features/auth/data/app_auth_coordinator.dart';
import '../../features/notifications/navigation/notification_destination.dart';

enum StripeConnectLinkAction { returnToSettings, refreshOnboarding }

StripeConnectLinkAction? stripeConnectLinkAction(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final isHttpsHost =
      scheme == 'https' && uri.host.toLowerCase() == 'athlete615.com';
  final isFallbackScheme =
      scheme == 'athletelab' && uri.host.toLowerCase() == 'connect';
  if (!isHttpsHost && !isFallbackScheme) return null;

  final path = isFallbackScheme ? '/connect${uri.path}' : uri.path;
  return switch (path) {
    '/connect/stripe/return' => StripeConnectLinkAction.returnToSettings,
    '/connect/stripe/refresh' => StripeConnectLinkAction.refreshOnboarding,
    _ => null,
  };
}

String stripeConnectDestination(StripeConnectLinkAction action) =>
    switch (action) {
      StripeConnectLinkAction.returnToSettings =>
        '/gym-settings?stripeConnect=return',
      StripeConnectLinkAction.refreshOnboarding =>
        '/gym-settings?stripeConnect=refresh',
    };

class PendingDeepLinkDestination {
  String? _destination;

  void remember(String destination) => _destination = destination;

  String? take() {
    final destination = _destination;
    _destination = null;
    return destination;
  }
}

final pendingDeepLinkDestination = PendingDeepLinkDestination();

String authenticatedRoute({
  required AppAuthState authState,
  required String destination,
  String? accessDestination,
}) => switch (authState) {
  AppAuthState.initializing || AppAuthState.refreshing => '/',
  AppAuthState.definitivelyUnauthenticated => '/login',
  AppAuthState.passwordRecoveryRequired => '/reset-password',
  AppAuthState.authenticated => accessDestination ?? destination,
};

void goToAuthenticatedDestination(GoRouter router, String destination) {
  final authState = appAuthCoordinator.state;
  if (authState != AppAuthState.authenticated) {
    pendingDeepLinkDestination.remember(destination);
  }
  router.go(
    authenticatedRoute(
      authState: authState,
      destination: destination,
      accessDestination: currentSessionAccessDestination,
    ),
  );
}

String? checkoutReturnDestination(Uri uri) {
  if (uri.scheme.toLowerCase() != 'athletelab' ||
      uri.host.toLowerCase() != 'checkout') {
    return null;
  }
  final status = uri.queryParameters['status'] == 'success'
      ? 'success'
      : 'cancel';
  return '/membership?checkout=$status';
}

String? workoutDeepLinkId(Uri uri) {
  final id =
      uri.queryParameters['id'] ??
      uri.queryParameters['workoutId'] ??
      uri.queryParameters['workout_id'];
  // Custom-scheme links put "workout" in the host; HTTPS links use the path.
  final destination = '${uri.host}${uri.path}'.toLowerCase();
  return destination.contains('workout') && id != null && id.isNotEmpty
      ? id
      : null;
}

class DeepLinkService {
  DeepLinkService(this._router);

  final GoRouter _router;
  final AppLinks _appLinks = AppLinks();

  StreamSubscription<Uri>? _linkSub;

  Future<void> start() async {
    final initialUri = await _appLinks.getInitialLink();

    if (initialUri != null) {
      await _handle(initialUri);
    }

    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      await _handle(uri);
    }, onError: (Object _) {});
  }

  Future<void> _handle(Uri uri) async {
    if (isPasswordRecoveryCallback(uri)) {
      final work = passwordRecoveryController.handleCallback(uri);
      _router.go('/reset-password');
      await work;
      return;
    }

    final checkoutDestination = checkoutReturnDestination(uri);
    if (checkoutDestination != null) {
      goToAuthenticatedDestination(_router, checkoutDestination);
      return;
    }

    final connectAction = stripeConnectLinkAction(uri);
    if (connectAction != null) {
      final destination = stripeConnectDestination(connectAction);
      goToAuthenticatedDestination(_router, destination);
      return;
    }

    final workoutId = workoutDeepLinkId(uri);
    if (workoutId != null) {
      final destination = await resolveWorkoutDestination(
        client: Supabase.instance.client,
        data: {'workoutId': workoutId},
      );
      goToAuthenticatedDestination(_router, destination);
      return;
    }
  }

  Future<void> dispose() async {
    await _linkSub?.cancel();
  }
}
