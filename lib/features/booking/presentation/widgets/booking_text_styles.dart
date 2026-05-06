import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BookingTextStyles {
  const BookingTextStyles._();

  static TextStyle displayTime = GoogleFonts.barlowCondensed(
    color: const Color(0xFF0E0E11),
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.7,
    height: 0.95,
  );

  static TextStyle classTitle = GoogleFonts.barlowCondensed(
    color: const Color(0xFF0E0E11),
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle metaLabel = GoogleFonts.barlowCondensed(
    color: const Color(0xFF8F96A3),
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.0,
  );

  static TextStyle metaValue = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.3,
  );

  static TextStyle button = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    height: 1.0,
  );

  static TextStyle headerBrand = GoogleFonts.barlowCondensed(
    color: const Color(0xFF090B12),
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle headerMonth = GoogleFonts.barlowCondensed(
    color: const Color(0xFF090B12),
    fontSize: 21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.0,
  );

  static TextStyle headerSubtitle = GoogleFonts.barlowCondensed(
    color: const Color(0xFF8F96A3),
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.0,
  );

  static TextStyle dayLabel({required bool selected}) =>
      GoogleFonts.barlowCondensed(
        color: selected ? const Color(0xFFB59B6A) : const Color(0xFF8F96A3),
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        height: 1.0,
      );

  static TextStyle dayNumber({required bool selected}) =>
      GoogleFonts.barlowCondensed(
        color: selected ? Colors.white : const Color(0xFF090B12),
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.0,
      );

  static TextStyle membership = GoogleFonts.barlowCondensed(
    color: const Color(0xFF149651),
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.05,
  );
}
