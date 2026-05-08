import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';

class WorkoutsHeader extends StatelessWidget {
  const WorkoutsHeader({
    super.key,
    required this.canManage,
    required this.onPrograms,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

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

  Widget _brandLogo() {
    return SizedBox(
      width: 132,
      child: Text(
        appStrings.appBrand,
        style: _font(
          18,
          weight: FontWeight.w800,
          color: const Color(0xFF0E0E11),
          letterSpacing: -0.3,
          height: 1.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayText = appStrings.formatHeaderDate(DateTime.now());

    return Container(
      color: Colors.white,
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
                    Padding(
                      padding: EdgeInsets.zero,
                      child: Text(
                        appStrings.workoutsTitle.toUpperCase(),
                        style: _font(
                          18,
                          weight: FontWeight.w800,
                          color: const Color(0xFF0E0E11),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      todayText,
                      style: _font(
                        12,
                        weight: FontWeight.w500,
                        color: const Color(0xFF8F96A3),
                        letterSpacing: 0.35,
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
                  child: _brandLogo(),
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
                      onTap: canManage ? onPrograms : onOpenNotifications,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F3EA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Badge(
                          isLabelVisible: unreadNotifications > 0 && !canManage,
                          label: Text(
                            unreadNotifications > 99
                                ? '99+'
                                : unreadNotifications.toString(),
                          ),
                          child: const Icon(
                            Icons.fitness_center_rounded,
                            size: 18,
                            color: Color(0xFFB59B6A),
                          ),
                        ),
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
