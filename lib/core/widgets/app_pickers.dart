import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData _pickerTheme(BuildContext context) {
  final base = Theme.of(context);

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: const Color(0xFFB59B6A),
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
        if (states.contains(WidgetState.selected))
          return const Color(0xFFB59B6A);
        return null;
      }),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return const Color(0xFFB59B6A);
      }),
      todayBorder: const BorderSide(color: Color(0xFFB59B6A)),
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
      dialHandColor: const Color(0xFFB59B6A),
      dialBackgroundColor: const Color(0xFFF4F5F7),
      entryModeIconColor: const Color(0xFFB59B6A),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFB59B6A),
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
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    builder: (context, child) {
      return Theme(data: _pickerTheme(context), child: child!);
    },
  );
}

Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (context, child) {
      return Theme(data: _pickerTheme(context), child: child!);
    },
  );
}
