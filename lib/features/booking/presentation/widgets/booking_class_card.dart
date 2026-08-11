import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';

class BookingClassCard extends StatelessWidget {
  const BookingClassCard({
    super.key,
    required this.klass,
    required this.bookedCount,
    required this.capacity,
    required this.buttonLabel,
    required this.buttonAction,
    required this.onTap,
    this.waitlistPosition,
    this.onMorePressed,
    required this.formatDateTime,
    this.isLoading = false,
  });

  final Map<String, dynamic> klass;
  final int bookedCount;
  final int capacity;
  final String buttonLabel;
  final VoidCallback? buttonAction;
  final VoidCallback? onTap;
  final int? waitlistPosition;
  final VoidCallback? onMorePressed;
  final String Function(String raw) formatDateTime;
  final bool isLoading;

  String _timeLabel(String raw) {
    final dt = DateTime.parse(raw).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String? _coachName() {
    final coach = klass['coach'];
    if (coach is! Map) return null;
    final name = coach['full_name']?.toString().trim();
    return name == null || name.isEmpty ? null : name;
  }

  String? _programName() {
    final program = klass['programs'];
    if (program is! Map) return null;
    final name = program['name']?.toString().trim();
    final title = klass['title']?.toString().trim();
    if (name == null || name.isEmpty || name == title) return null;
    return name;
  }

  bool get _booked =>
      buttonLabel == appStrings.bookingBooked ||
      buttonLabel == appStrings.bookingCancel;

  @override
  Widget build(BuildContext context) {
    final coach = _coachName();
    final program = _programName();
    final full = capacity > 0 && bookedCount >= capacity;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border(context), width: 0.8),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  _timeLabel(klass['starts_at'].toString()),
                  style: GoogleFonts.barlowCondensed(
                    color: AppColors.textPrimary(context),
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (klass['title']?.toString() ?? appStrings.classFallback)
                          .toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.itemTitle(context),
                    ),
                    if (program != null)
                      Text(program, style: AppTypography.helper(context)),
                    if (coach != null)
                      Text(
                        '${appStrings.coach} · $coach',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySecondary(context),
                      ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '$bookedCount / $capacity ${appStrings.spots.toLowerCase()}',
                      style: AppTypography.helper(context).copyWith(
                        color: full
                            ? AppColors.textPrimary(context)
                            : AppColors.textSecondary(context),
                        fontWeight: full ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (_booked || waitlistPosition != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _booked
                                    ? AppColors.success
                                    : AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                _booked
                                    ? appStrings.bookingBooked
                                    : appStrings.bookingWaitlistPosition(
                                        waitlistPosition!,
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.helper(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (onMorePressed != null)
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: AppSizes.minimumTouchTarget,
                        height: AppSizes.minimumTouchTarget,
                      ),
                      onPressed: onMorePressed,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 104,
                      minHeight: AppSizes.minimumTouchTarget,
                      maxWidth: 128,
                    ),
                    child: FilledButton(
                      onPressed: buttonAction,
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppColors.textPrimary(context),
                        disabledBackgroundColor: AppColors.surfaceAlt(context),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: AppColors.textSecondary(
                          context,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.input),
                        ),
                      ),
                      child: Text(
                        isLoading ? '…' : buttonLabel.toUpperCase(),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.buttonLabel(context).copyWith(
                          color: buttonAction == null
                              ? AppColors.textSecondary(context)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
