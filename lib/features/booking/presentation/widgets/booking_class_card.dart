import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'booking_text_styles.dart';

class BookingClassCard extends StatelessWidget {
  const BookingClassCard({
    super.key,
    required this.klass,
    required this.bookedCount,
    required this.capacity,
    required this.buttonLabel,
    required this.buttonAction,
    required this.canManageAttendance,
    required this.onOpenAttendance,
    this.onMorePressed,
    required this.formatDateTime,
    this.isLoading = false,
  });

  final Map<String, dynamic> klass;
  final int bookedCount;
  final int capacity;
  final String buttonLabel;
  final VoidCallback? buttonAction;
  final bool canManageAttendance;
  final VoidCallback? onOpenAttendance;
  final VoidCallback? onMorePressed;
  final String Function(String raw) formatDateTime;
  final bool isLoading;

  String _timeLabel(String raw) {
    final dt = DateTime.parse(raw).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  bool get _isBooked => buttonLabel == appStrings.bookingBooked;

  @override
  Widget build(BuildContext context) {
    final title =
        klass['title']?.toString().toUpperCase() ??
        appStrings.classFallback.toUpperCase();

    final program = klass['programs'] as Map<String, dynamic>?;
    final programImageUrl = program?['image_url']?.toString().trim();
    final hasProgramImage =
        programImageUrl != null && programImageUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: hasProgramImage
                    ? Image.network(
                        programImageUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                      )
                    : const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Color(0xFF111111),
                              Color(0xFF252525),
                              Color(0xFF323232),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF111111),
                      const Color(0xFF171717).withValues(alpha: 0.94),
                      const Color(0xFF252525).withValues(alpha: 0.58),
                    ],
                    stops: const [0.0, 0.46, 1.0],
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: canManageAttendance ? onOpenAttendance : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _timeLabel(klass['starts_at']),
                            style: BookingTextStyles.displayTime,
                          ),
                          const Spacer(),
                          _InlineSpots(value: '$bookedCount / $capacity'),
                          if (onMorePressed != null) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.more_horiz,
                                color: Color(0xFFABABAB),
                              ),
                              onPressed: onMorePressed,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: BookingTextStyles.classTitle,
                            ),
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 132,
                            child: _ActionButton(
                              label: isLoading
                                  ? '...'
                                  : buttonLabel.toUpperCase(),
                              onPressed: buttonAction,
                              filled: buttonAction != null,
                            ),
                          ),
                        ],
                      ),
                      if (_isBooked) ...[
                        const SizedBox(height: 8),
                        _StatusPill(
                          label: appStrings.bookingBooked.toUpperCase(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineSpots extends StatelessWidget {
  const _InlineSpots({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appStrings.spots.toUpperCase(),
          style: BookingTextStyles.metaLabel,
        ),
        const SizedBox(width: 6),
        Text(value, style: BookingTextStyles.metaValue),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EDE1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9B7F4A),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: filled
              ? const Color(0xFFBCA36D)
              : const Color(0xFFF0F1F4),
          disabledBackgroundColor: const Color(0xFFF0F1F4),
          foregroundColor: filled ? Colors.white : const Color(0xFF384052),
          disabledForegroundColor: const Color(0xFF8F96A3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label, style: BookingTextStyles.button),
      ),
    );
  }
}
