import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTimeFormat { twentyFourHour, twelveHour }

class AppPreferencesController extends ChangeNotifier {
  static const _timeFormatKey = 'app_time_format';

  AppTimeFormat _timeFormat = AppTimeFormat.twentyFourHour;

  AppTimeFormat get timeFormat => _timeFormat;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _timeFormat = prefs.getString(_timeFormatKey) == 'twelveHour'
        ? AppTimeFormat.twelveHour
        : AppTimeFormat.twentyFourHour;
    notifyListeners();
  }

  Future<void> setTimeFormat(AppTimeFormat value) async {
    _timeFormat = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_timeFormatKey, value.name);
    notifyListeners();
  }

  String formatTime(DateTime date, {String? locale}) {
    final minute = date.minute.toString().padLeft(2, '0');
    if (_timeFormat == AppTimeFormat.twentyFourHour) {
      return '${date.hour.toString().padLeft(2, '0')}:$minute';
    }
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
  }
}

final appPreferencesController = AppPreferencesController();
