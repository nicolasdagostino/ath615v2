import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';

class AppPrimaryGymHeader extends StatelessWidget {
  const AppPrimaryGymHeader({super.key, this.gymName, this.action});

  final String? gymName;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('app-primary-gym-header'),
    width: double.infinity,
    child: ColoredBox(
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
                    horizontal: action == null
                        ? 0
                        : AppSizes.minimumTouchTarget,
                  ),
                  child: gymName?.trim().isNotEmpty == true
                      ? Text(
                          gymName!.trim().toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                        )
                      : ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            'assets/images/logo_negro.png',
                            key: const ValueKey('app-primary-a615-logo'),
                            height: 38,
                            fit: BoxFit.contain,
                            semanticLabel: 'A615',
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
    ),
  );
}
