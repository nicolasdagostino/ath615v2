import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/locale/locale_controller.dart';
import 'package:intl/intl.dart';

class BookingHeader extends StatelessWidget {
  const BookingHeader({
    super.key,
    required this.selectedDay,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final DateTime selectedDay;
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
    final dayText = DateFormat(
      'EEEE, MMMM d',
      localeController.locale.languageCode,
    ).format(selectedDay);

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
                    Text(
                      appStrings.bookingTitle.toUpperCase(),
                      style: _font(
                        18,
                        weight: FontWeight.w800,
                        color: const Color(0xFF0E0E11),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dayText,
                      style: _font(
                        12,
                        weight: FontWeight.w500,
                        color: const Color(0xFF8F96A3),
                        letterSpacing: 0.3,
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
                      onTap: onOpenNotifications,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F3EA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Badge(
                          isLabelVisible: unreadNotifications > 0,
                          label: Text(
                            unreadNotifications > 99
                                ? '99+'
                                : unreadNotifications.toString(),
                          ),
                          child: const Icon(
                            Icons.notifications_outlined,
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
