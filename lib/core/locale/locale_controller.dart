import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController extends ChangeNotifier {
  static const _key = 'app_language';

  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key) ?? 'en';
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (code != 'en' && code != 'es') return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);

    _locale = Locale(code);
    notifyListeners();
  }
}

final localeController = LocaleController();
