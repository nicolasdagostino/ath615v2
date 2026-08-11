import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTypography {
  const AppTypography._();

  static TextStyle sectionTitle(BuildContext context) =>
      GoogleFonts.barlowCondensed(
        color: AppColors.textPrimary(context),
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        height: 1.1,
      );

  static TextStyle itemTitle(BuildContext context) =>
      GoogleFonts.barlowCondensed(
        color: AppColors.textPrimary(context),
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        height: 1.1,
      );

  static TextStyle buttonLabel(BuildContext context) =>
      GoogleFonts.barlowCondensed(
        color: AppColors.textPrimary(context),
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        height: 1,
      );

  static TextStyle body(BuildContext context) => GoogleFonts.barlow(
    color: AppColors.textPrimary(context),
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static TextStyle bodySecondary(BuildContext context) => GoogleFonts.barlow(
    color: AppColors.textSecondary(context),
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static TextStyle helper(BuildContext context) => GoogleFonts.barlow(
    color: AppColors.textSecondary(context),
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static TextStyle error(BuildContext context) => GoogleFonts.barlow(
    color: AppColors.danger,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
}
