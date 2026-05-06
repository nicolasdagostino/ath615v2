import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WorkoutTextStyles {
  const WorkoutTextStyles._();

  static TextStyle headerBrand = GoogleFonts.barlowCondensed(
    color: const Color(0xFF090B12),
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle headerTitle = GoogleFonts.barlowCondensed(
    color: const Color(0xFF090B12),
    fontSize: 25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    height: 1,
  );

  static TextStyle headerSubtitle = GoogleFonts.barlowCondensed(
    color: const Color(0xFF8F96A3),
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1,
  );

  static TextStyle program = GoogleFonts.barlowCondensed(
    color: const Color(0xFFB59B6A),
    fontSize: 23,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    height: 1,
  );

  static TextStyle date = GoogleFonts.barlowCondensed(
    color: const Color(0xFF8F96A3),
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.3,
  );

  static TextStyle stat = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384052),
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
    height: 1,
  );

  static TextStyle button = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    height: 1,
  );

  static TextStyle emptyTitle = GoogleFonts.barlowCondensed(
    color: const Color(0xFF111318),
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle emptyMessage = GoogleFonts.barlowCondensed(
    color: const Color(0xFF8F96A3),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}
