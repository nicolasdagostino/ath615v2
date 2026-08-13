import 'package:flutter/material.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_selected_date_label.dart';
import '../booking_colors.dart';

class BookingHeader extends StatelessWidget {
  const BookingHeader({super.key, required this.gymName});

  final String? gymName;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BookingColors.primary,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: AppSizes.mainHeaderHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
            child: Center(
              child: Text(
                (gymName ?? appStrings.appBrand).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookingClassesChip extends StatelessWidget {
  const BookingClassesChip({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      key: const ValueKey('booking-classes-chip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: BookingColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: Text(
        appStrings.bookingClasses.toUpperCase(),
        style: AppTypography.buttonLabel(
          context,
        ).copyWith(color: Colors.white, letterSpacing: 0.6),
      ),
    ),
  );
}

class BookingSelectedDateLabel extends StatelessWidget {
  const BookingSelectedDateLabel({super.key, required this.selectedDay});

  final DateTime selectedDay;

  @override
  Widget build(BuildContext context) =>
      AppSelectedDateLabel(selectedDate: selectedDay);
}
