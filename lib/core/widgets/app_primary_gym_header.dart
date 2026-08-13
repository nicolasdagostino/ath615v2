import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';

class AppPrimaryGymHeader extends StatelessWidget {
  const AppPrimaryGymHeader({super.key, this.gymName});

  final String? gymName;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('app-primary-gym-header'),
    color: AppColors.primary,
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: AppSizes.mainHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
          child: Center(
            child: Text(
              (gymName?.trim().isNotEmpty == true
                      ? gymName!.trim()
                      : appStrings.appBrand)
                  .toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
