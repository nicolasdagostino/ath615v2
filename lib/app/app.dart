import 'package:flutter/material.dart';

import '../core/router/app_router.dart';
import '../core/router/deep_link_service.dart';
import '../core/theme/app_theme.dart';

class AthleteLabApp extends StatefulWidget {
  const AthleteLabApp({super.key});

  @override
  State<AthleteLabApp> createState() => _AthleteLabAppState();
}

class _AthleteLabAppState extends State<AthleteLabApp> {
  late final _router = AppRouter.router;
  late final _deepLinks = DeepLinkService(_router);

  @override
  void initState() {
    super.initState();
    print('ATH615 APP INIT');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('ATH615 STARTING DEEPLINK SERVICE');
      _deepLinks.start();
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
