import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppRadii {
  const AppRadii._();

  static const double card = 16;
  static const double sheet = 22;
  static const double panel = 18;
  static const double input = 10;
  static const double button = 16;
  static const double pill = 999;
}

class AppSpacing {
  const AppSpacing._();

  static const double screenX = 24;
  static const double cardPadding = 22;
  static const double sheetMargin = 16;
}

class AppShadows {
  const AppShadows._();

  static List<BoxShadow> card(BuildContext context) {
    return [
      BoxShadow(
        color: Colors.black.withValues(
          alpha: AppColors.isDark(context) ? 0.18 : 0.04,
        ),
        blurRadius: AppColors.isDark(context) ? 24 : 24,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> soft(BuildContext context) {
    return [
      BoxShadow(
        color: Colors.black.withValues(
          alpha: AppColors.isDark(context) ? 0.14 : 0.035,
        ),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
