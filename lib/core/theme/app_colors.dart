import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static const accent = Color(0xFFB59B6A);
  static const danger = Color(0xFFB42318);
  static const success = Color(0xFF24835B);

  static Color background(BuildContext context) =>
      isDark(context) ? const Color(0xFF171717) : const Color(0xFFF7F8FA);

  static Color surface(BuildContext context) =>
      isDark(context) ? const Color(0xFF252525) : Colors.white;

  static Color surfaceAlt(BuildContext context) =>
      isDark(context) ? const Color(0xFF171717) : const Color(0xFFF4F5F7);

  static Color border(BuildContext context) =>
      isDark(context) ? const Color(0xFF323232) : const Color(0xFFE6E8EC);

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF0E0E11);

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFABABAB) : const Color(0xFF6B7280);

  static Color muted(BuildContext context) =>
      isDark(context) ? const Color(0xFF8F96A3) : const Color(0xFF8F96A3);
}
