import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

class AppSelectedDateLabel extends StatelessWidget {
  const AppSelectedDateLabel({super.key, required this.selectedDate});

  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    final locale = appStrings.isEs ? 'es' : 'en';
    final label = DateFormat(
      'EEEE, d MMMM y',
      locale,
    ).format(selectedDate).toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          textAlign: TextAlign.left,
          style: AppTypography.bodySecondary(context).copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.35,
          ),
        ),
      ),
    );
  }
}
