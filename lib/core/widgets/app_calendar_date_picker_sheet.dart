import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';

Future<DateTime?> showAppCalendarDatePickerSheet({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required Color accentColor,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: 0.46),
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.88,
    child: AppCalendarDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      accentColor: accentColor,
    ),
  ),
);

class AppCalendarDatePickerSheet extends StatelessWidget {
  const AppCalendarDatePickerSheet({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.accentColor,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('app-calendar-date-picker-sheet'),
    color: AppColors.surface(context),
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(AppRadii.sheet),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenX,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      appStrings.pick('SELECT DATE', 'SELECCIONAR FECHA'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('app-calendar-date-picker-close'),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    onPressed: Navigator.of(context).pop,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: accentColor,
                onPrimary: Colors.white,
                surface: AppColors.surface(context),
                onSurface: AppColors.textPrimary(context),
              ),
            ),
            child: CalendarDatePicker(
              key: const ValueKey('app-calendar-date-picker'),
              initialDate: initialDate,
              firstDate: firstDate,
              lastDate: lastDate,
              onDateChanged: (date) => Navigator.pop(context, date),
            ),
          ),
        ),
      ],
    ),
  );
}
