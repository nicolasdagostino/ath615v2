import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/router/app_router.dart';
import '../core/router/deep_link_service.dart';
import '../core/theme/app_theme.dart';

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

    print('PUSH APNS TOKEN => $apnsToken');

    if (apnsToken == null) {
      print('PUSH SKIPPED => APNS token null');
      return;
    }

    final token = await messaging.getToken();
    print('PUSH TOKEN => $token');

    final user = Supabase.instance.client.auth.currentUser;

    if (token == null || user == null) {
      print('PUSH SKIPPED => user or token null');
      return;
    }

    await Supabase.instance.client.from('device_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': 'ios',
    });

    print('PUSH TOKEN SAVED');
  } catch (e) {
    print('PUSH SETUP ERROR => $e');
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

  void _openWorkoutFromPush(RemoteMessage message) {
    final workoutId =
        message.data['workoutId'] ??
        message.data['workout_id'] ??
        message.data['id'];

    print('PUSH OPEN DATA => ${message.data}');

    if (workoutId == null || workoutId.toString().isEmpty) return;

    _router.go('/workout/${workoutId.toString()}');
  }

  @override
  void initState() {
    super.initState();
    print('ATH615 APP INIT');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('ATH615 STARTING DEEPLINK SERVICE');
      _deepLinks.start();

      Future.delayed(const Duration(seconds: 2), () {
        setupPush();
      });

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
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Athlete 615',
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}
