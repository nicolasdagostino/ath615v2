import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'app_calendar_date_picker_sheet.dart';

ThemeData _pickerTheme(BuildContext context, Color accentColor) {
  final base = Theme.of(context);

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: accentColor,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF0E0E11),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      headerBackgroundColor: const Color(0xFF0E0E11),
      headerForegroundColor: Colors.white,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return const Color(0xFF0E0E11);
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentColor;
        }
        return null;
      }),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return accentColor;
      }),
      todayBorder: BorderSide(color: accentColor),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      hourMinuteColor: const Color(0xFFF4F5F7),
      dialHandColor: accentColor,
      dialBackgroundColor: const Color(0xFFF4F5F7),
      entryModeIconColor: accentColor,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentColor,
        textStyle: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    ),
  );
}

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  Color accentColor = AppColors.primary,
}) {
  final normalizedFirst = DateTime(
    firstDate.year,
    firstDate.month,
    firstDate.day,
  );
  final normalizedLast = DateTime(lastDate.year, lastDate.month, lastDate.day);
  final normalizedInitial = DateTime(
    initialDate.year,
    initialDate.month,
    initialDate.day,
  );
  final effectiveInitial = normalizedInitial.isBefore(normalizedFirst)
      ? normalizedFirst
      : normalizedInitial.isAfter(normalizedLast)
      ? normalizedLast
      : normalizedInitial;
  return showAppCalendarDatePickerSheet(
    context: context,
    initialDate: effectiveInitial,
    firstDate: normalizedFirst,
    lastDate: normalizedLast,
    accentColor: accentColor,
  );
}

Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  Color accentColor = const Color(0xFFB59B6A),
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (context, child) {
      return Theme(data: _pickerTheme(context, accentColor), child: child!);
    },
  );
}
