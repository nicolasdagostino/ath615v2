import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/preferences/app_preferences_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../booking_colors.dart';
import '../booking_occupancy.dart';

class BookingClassCard extends StatelessWidget {
  const BookingClassCard({
    super.key,
    required this.klass,
    required this.bookedCount,
    required this.capacity,
    required this.buttonLabel,
    required this.buttonAction,
    required this.onTap,
    this.bookedProfiles = const [],
    this.waitlistPosition,
    required this.formatDateTime,
    this.isLoading = false,
  });

  final Map<String, dynamic> klass;
  final int bookedCount;
  final int capacity;
  final String buttonLabel;
  final VoidCallback? buttonAction;
  final VoidCallback? onTap;
  final List<Map<String, dynamic>> bookedProfiles;
  final int? waitlistPosition;
  final String Function(String raw) formatDateTime;
  final bool isLoading;

  String _timeLabel(String raw) {
    final dt = DateTime.parse(raw).toLocal();
    return appPreferencesController.formatTime(
      dt,
      locale: appStrings.isEs ? 'es' : 'en',
    );
  }

  String? _programName() {
    final program = klass['programs'];
    if (program is! Map) return null;
    final name = program['name']?.toString().trim();
    return name == null || name.isEmpty ? null : name;
  }

  bool get _booked =>
      buttonLabel == appStrings.bookingBooked ||
      buttonLabel == appStrings.bookingCancel;

  bool get _destructive =>
      buttonLabel == appStrings.bookingCancel ||
      buttonLabel == appStrings.bookingLeaveWaitlist;

  bool get _available =>
      buttonLabel == appStrings.bookingBook ||
      buttonLabel == appStrings.bookingJoinWaitlist;

  @override
  Widget build(BuildContext context) {
    final title = (klass['title']?.toString() ?? appStrings.classFallback)
        .trim();
    final program = _programName();
    final primaryName = (program ?? title).toUpperCase();
    final showClassName = program != null && program != title;
    final occupancy = bookingOccupancy(
      bookedCount: bookedCount,
      capacity: capacity,
    );
    final occupancyLabel = switch (occupancy) {
      BookingOccupancy.available => appStrings.bookingAvailable,
      BookingOccupancy.almostFull => appStrings.bookingAlmostFull,
      BookingOccupancy.full => appStrings.bookingFull,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          side: BorderSide(color: AppColors.border(context), width: 0.7),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _timeLabel(klass['starts_at'].toString()),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          height: 1.1,
                        ),
                      ),
                    ),
                    _BookingStateAction(
                      label: buttonLabel,
                      loading: isLoading,
                      enabled: buttonAction != null,
                      destructive: _destructive,
                      available: _available,
                      onPressed: buttonAction,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  primaryName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$occupancyLabel · $bookedCount / $capacity ${appStrings.spots.toLowerCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySecondary(context).copyWith(
                          color: occupancy == BookingOccupancy.full
                              ? AppColors.textPrimary(context)
                              : AppColors.textSecondary(context),
                          fontWeight: occupancy == BookingOccupancy.full
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (bookedProfiles.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      BookingAvatarStack(profiles: bookedProfiles),
                    ],
                  ],
                ),
                if (showClassName) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context).copyWith(
                      color: AppColors.textSecondary(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (_booked || waitlistPosition != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _booked
                              ? AppColors.success
                              : BookingColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BookingAvatarStack extends StatelessWidget {
  const BookingAvatarStack({
    super.key,
    required this.profiles,
    this.maxVisible = 4,
  });

  final List<Map<String, dynamic>> profiles;
  final int maxVisible;

  static const double _diameter = 26;
  static const double _overlap = 7;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) return const SizedBox.shrink();

    final visibleCount = profiles.length.clamp(0, maxVisible);
    final overflowCount = profiles.length - visibleCount;
    final avatarsWidth =
        _diameter + (visibleCount - 1) * (_diameter - _overlap);

    return Row(
      key: const ValueKey('booking-avatar-stack'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: avatarsWidth,
          height: _diameter,
          child: Stack(
            children: [
              for (var index = 0; index < visibleCount; index++)
                Positioned(
                  left: index * (_diameter - _overlap),
                  child: _BookingStackAvatar(profile: profiles[index]),
                ),
            ],
          ),
        ),
        if (overflowCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '+$overflowCount',
            key: const ValueKey('booking-avatar-overflow'),
            style: AppTypography.helper(context).copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _BookingStackAvatar extends StatelessWidget {
  const _BookingStackAvatar({required this.profile});

  final Map<String, dynamic> profile;

  String get _initials {
    final name = profile['full_name']?.toString().trim() ?? '';
    if (name.isEmpty) return 'M';
    return name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile['avatar_url']?.toString().trim();
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return Container(
      key: ValueKey('booking-avatar-${profile['id']}'),
      width: BookingAvatarStack._diameter,
      height: BookingAvatarStack._diameter,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        shape: BoxShape.circle,
      ),
      child: AppAvatar(
        name: profile['full_name']?.toString() ?? _initials,
        avatarUrl: hasAvatar ? avatarUrl : null,
        size: BookingAvatarStack._diameter - 3,
        foregroundColor: BookingColors.primary,
        fallbackKey: const ValueKey('booking-avatar-fallback'),
        textStyle: AppTypography.buttonLabel(
          context,
        ).copyWith(color: BookingColors.primary, fontSize: 9),
      ),
    );
  }
}

class _BookingStateAction extends StatelessWidget {
  const _BookingStateAction({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.destructive,
    required this.available,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final bool destructive;
  final bool available;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.danger
        : available
        ? BookingColors.primary
        : AppColors.textSecondary(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppSizes.minimumTouchTarget,
        maxWidth: 118,
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.minimumTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          foregroundColor: color,
          disabledForegroundColor: color,
          backgroundColor: color.withValues(alpha: enabled ? 0.07 : 0.04),
          disabledBackgroundColor: color.withValues(alpha: 0.04),
          side: BorderSide(color: color.withValues(alpha: 0.65)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
        ),
        child: Text(
          loading ? '…' : label.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.buttonLabel(
            context,
          ).copyWith(color: color, fontSize: 11.5, letterSpacing: 0.45),
        ),
      ),
    );
  }
}
