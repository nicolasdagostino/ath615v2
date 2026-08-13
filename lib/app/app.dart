import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/router/app_router.dart';
import '../core/router/deep_link_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/locale/locale_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/notifications/data/notifications_repository.dart';

class AthleteLabApp extends StatefulWidget {
  const AthleteLabApp({super.key});

  @override
  State<AthleteLabApp> createState() => _AthleteLabAppState();
}

class _AthleteLabAppState extends State<AthleteLabApp> {
  late final _router = AppRouter.router;
  late final _deepLinks = DeepLinkService(_router);
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  Timer? _initialPushTimer;
  Future<void> _pushWork = Future.value();
  bool _pushSetupScheduled = false;
  bool _pushSetupPending = false;

  String? get _pushPlatform {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => null,
    };
  }

  void _enqueuePushWork(Future<void> Function() work) {
    _pushWork = _pushWork.then((_) => work()).catchError((Object error) {
      debugPrint('PUSH ERROR => $error');
    });
  }

  void _schedulePushSetup() {
    if (!mounted) return;
    if (_pushSetupScheduled) {
      _pushSetupPending = true;
      return;
    }
    _pushSetupScheduled = true;
    _enqueuePushWork(() async {
      try {
        await _setupPush();
      } finally {
        _pushSetupScheduled = false;
        if (_pushSetupPending && mounted) {
          _pushSetupPending = false;
          _schedulePushSetup();
        }
      }
    });
  }

  Future<void> _persistPushToken(String token) async {
    if (!mounted || AuthRepository.isSigningOut) return;

    final normalizedToken = token.trim();
    final platform = _pushPlatform;
    final user = Supabase.instance.client.auth.currentUser;

    if (normalizedToken.isEmpty || platform == null || user == null) {
      debugPrint('PUSH SKIPPED => user, token, or platform unavailable');
      return;
    }

    await Supabase.instance.client
        .from('device_tokens')
        .delete()
        .eq('platform', platform)
        .eq('user_id', user.id);

    await Supabase.instance.client
        .from('device_tokens')
        .delete()
        .eq('token', normalizedToken)
        .neq('user_id', user.id);

    if (AuthRepository.isSigningOut) return;

    await Supabase.instance.client.from('device_tokens').upsert({
      'user_id': user.id,
      'token': normalizedToken,
      'platform': platform,
    }, onConflict: 'user_id,token');

    debugPrint('PUSH TOKEN SAVED');
  }

  Future<void> _setupPush() async {
    try {
      final platform = _pushPlatform;
      if (platform == null) {
        debugPrint('PUSH SKIPPED => unsupported platform');
        return;
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      if (!mounted) return;

      if (platform == 'ios') {
        String? apnsToken;
        for (var i = 0; i < 10 && mounted; i++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken != null) break;
          await Future.delayed(const Duration(seconds: 1));
        }

        if (!mounted) return;
        debugPrint('PUSH APNS TOKEN AVAILABLE');

        if (apnsToken == null) {
          debugPrint('PUSH SKIPPED => APNS token null');
          return;
        }
      }

      final token = await messaging.getToken();
      if (!mounted) return;
      debugPrint('PUSH FCM TOKEN AVAILABLE');

      if (token == null) {
        debugPrint('PUSH SKIPPED => token null');
        return;
      }

      await _persistPushToken(token);
    } catch (e) {
      debugPrint('PUSH SETUP ERROR => $e');
    }
  }

  void _handlePushTap(RemoteMessage message) {
    final type = message.data['type']?.toString();
    final workoutId = message.data['workoutId'] ?? message.data['workout_id'];
    final notificationId =
        message.data['notificationId'] ?? message.data['notification_id'];

    debugPrint('PUSH OPEN DATA => ${message.data}');

    if (notificationId != null && notificationId.toString().trim().isNotEmpty) {
      SupabaseNotificationsRepository(
        Supabase.instance.client,
      ).markRead(notificationId.toString()).ignore();
    }

    if (workoutId != null && workoutId.toString().trim().isNotEmpty) {
      _router.push('/workout/${workoutId.toString()}');
      return;
    }

    if (type == 'membership_request') {
      _router.go('/app?section=membership');
      return;
    }

    if (notificationId != null && notificationId.toString().trim().isNotEmpty) {
      final encodedId = Uri.encodeQueryComponent(notificationId.toString());
      _router.push('/notifications?notificationId=$encodedId');
    }
  }

  void _showForegroundPush(RemoteMessage message) {
    notificationsInboxEvents.refresh();
    final title = message.notification?.title ?? 'Notification';
    final body = message.notification?.body ?? '';

    final messenger = _messengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            if (body.isNotEmpty) Text(body),
          ],
        ),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => _handlePushTap(message),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    debugPrint('ATH615 APP INIT');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('ATH615 STARTING DEEPLINK SERVICE');
      _deepLinks.start();

      _initialPushTimer = Timer(const Duration(seconds: 2), () {
        _schedulePushSetup();
      });

      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            final authenticated =
                state.event == AuthChangeEvent.initialSession ||
                state.event == AuthChangeEvent.signedIn;
            if (!authenticated || state.session == null) return;
            _initialPushTimer?.cancel();
            _schedulePushSetup();
          });

      _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
          .listen((token) {
            _enqueuePushWork(() => _persistPushToken(token));
          });

      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
        _showForegroundPush,
      );

      _openedMessageSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handlePushTap,
      );

      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (mounted && message != null) {
          _handlePushTap(message);
        }
      });
    });
  }

  @override
  void dispose() {
    _initialPushTimer?.cancel();
    _tokenRefreshSubscription?.cancel();
    _authSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _openedMessageSubscription?.cancel();
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([localeController, themeController]),
      builder: (context, _) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Athlete 615',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeController.themeMode,
          locale: localeController.locale,
          supportedLocales: const [Locale('en'), Locale('es')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scaffoldMessengerKey: _messengerKey,
          routerConfig: _router,
        );
      },
    );
  }
}
