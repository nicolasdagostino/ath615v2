import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';

class WorkoutsHeader extends StatelessWidget {
  const WorkoutsHeader({
    super.key,
    required this.gymName,
    required this.canManage,
    required this.onPrograms,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final String? gymName;
  final bool canManage;
  final VoidCallback onPrograms;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  TextStyle _font(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = const Color(0xFF111318),
    double letterSpacing = 0,
    double height = 1.0,
  }) {
    return GoogleFonts.barlowCondensed(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  Widget _brandLogo(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Text(
        gymName ?? appStrings.appBrand,
        style: _font(
          16,
          weight: FontWeight.w800,
          color: AppColors.textPrimary(context),
          letterSpacing: -0.3,
          height: 1.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background(context),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.workoutsTitle.toUpperCase(),
                      style: _font(
                        22,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _brandLogo(context),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: 132,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (canManage) ...[
                        _HeaderIconButton(
                          icon: Icons.fitness_center_rounded,
                          onTap: onPrograms,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _HeaderIconButton(
                        icon: Icons.notifications,
                        onTap: onOpenNotifications,
                        badgeCount: unreadNotifications,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: icon == Icons.notifications ? 32 : 28,
              color: AppColors.accent,
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -7,
              top: -7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
