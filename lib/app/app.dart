import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/router/app_router.dart';
import '../core/router/deep_link_service.dart';
import '../core/theme/app_theme.dart';
import '../core/locale/locale_controller.dart';

Future<void> setupPush() async {
  try {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    String? apnsToken;
    for (var i = 0; i < 10; i++) {
      apnsToken = await messaging.getAPNSToken();
      if (apnsToken != null) break;
      await Future.delayed(const Duration(seconds: 1));
    }

    debugPrint('PUSH APNS TOKEN => $apnsToken');

    if (apnsToken == null) {
      debugPrint('PUSH SKIPPED => APNS token null');
      return;
    }

    final token = await messaging.getToken();
    debugPrint('PUSH TOKEN => $token');

    final user = Supabase.instance.client.auth.currentUser;

    if (token == null || user == null) {
      debugPrint('PUSH SKIPPED => user or token null');
      return;
    }

    await Supabase.instance.client.from('device_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': 'ios',
    }, onConflict: 'user_id,token');

    debugPrint('PUSH TOKEN SAVED');
  } catch (e) {
    debugPrint('PUSH SETUP ERROR => $e');
  }
}

class AthleteLabApp extends StatefulWidget {
  const AthleteLabApp({super.key});

  @override
  State<AthleteLabApp> createState() => _AthleteLabAppState();
}

class _AthleteLabAppState extends State<AthleteLabApp> {
  late final _router = AppRouter.router;
  late final _deepLinks = DeepLinkService(_router);
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  void _openWorkoutFromPush(RemoteMessage message) {
    final workoutId =
        message.data['workoutId'] ??
        message.data['workout_id'] ??
        message.data['id'];

    final notificationId = message.data['notificationId'];

    if (notificationId != null) {
      Supabase.instance.client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notificationId)
          .ignore();
    }

    debugPrint('PUSH OPEN DATA => ${message.data}');

    if (workoutId == null || workoutId.toString().isEmpty) return;

    _router.push('/workout/${workoutId.toString()}');
  }

  void _showForegroundPush(RemoteMessage message) {
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
          onPressed: () => _openWorkoutFromPush(message),
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

      Future.delayed(const Duration(seconds: 2), () {
        setupPush();
      });

      FirebaseMessaging.onMessage.listen(_showForegroundPush);

      FirebaseMessaging.onMessageOpenedApp.listen(_openWorkoutFromPush);

      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          _openWorkoutFromPush(message);
        }
      });
    });
  }

  @override
  void dispose() {
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Athlete 615',
          theme: AppTheme.light,
          locale: localeController.locale,
          supportedLocales: const [Locale('en'), Locale('es')],
          scaffoldMessengerKey: _messengerKey,
          routerConfig: _router,
        );
      },
    );
  }
}
