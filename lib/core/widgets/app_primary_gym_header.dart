import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';

class AppPrimaryGymHeader extends StatelessWidget {
  const AppPrimaryGymHeader({super.key, this.gymName, this.action});

  final String? gymName;
  final Widget? action;

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
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: action == null ? 0 : AppSizes.minimumTouchTarget,
                ),
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
              if (action != null)
                Align(alignment: Alignment.centerRight, child: action!),
            ],
          ),
        ),
      ),
    ),
  );
}
