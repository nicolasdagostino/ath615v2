import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';

class ExploreHeader extends StatelessWidget {
  const ExploreHeader({
    super.key,
    required this.gymName,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final String? gymName;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  TextStyle _font(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = const Color(0xFF111318),
    double? letterSpacing,
    double? height,
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
          18,
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
      color: AppColors.surfaceAlt(context),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
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
                      appStrings.exploreTitle.toUpperCase(),
                      style: _font(
                        24,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                        letterSpacing: -0.4,
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
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onOpenNotifications,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(
                              Icons.notifications_outlined,
                              size: 28,
                              color: AppColors.accent,
                            ),
                          ),
                          if (unreadNotifications > 0)
                            Positioned(
                              right: -7,
                              top: -7,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.danger,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  unreadNotifications > 99
                                      ? '99+'
                                      : unreadNotifications.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
