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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: canManageAttendance ? onOpenAttendance : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeLabel(klass['starts_at']),
                      style: BookingTextStyles.displayTime,
                    ),
                    const Spacer(),
                    if (_isBooked)
                      _StatusPill(
                        label: appStrings.bookingBooked.toUpperCase(),
                      ),
                    if (onMorePressed != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_horiz),
                        onPressed: onMorePressed,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(title, style: BookingTextStyles.classTitle),
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFEDEFF3)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MetaBlock(
                        label: 'COACH',
                        value:
                            klass['coach_name']?.toString() ??
                            'Nicolás D’Agostino',
                      ),
                    ),
                    _MetaBlock(
                      label: 'SPOTS',
                      value: '$bookedCount / $capacity',
                      alignEnd: true,
                    ),
                  ],
                ),
                if (canManageAttendance) ...[
                  const SizedBox(height: 14),
                  _ActionButton(
                    label: 'ROSTER',
                    onPressed: onOpenAttendance,
                    filled: false,
                  ),
                ],
                const SizedBox(height: 14),
                _ActionButton(
                  label: buttonLabel.toUpperCase(),
                  onPressed: buttonAction,
                  filled: buttonAction != null,
                ),
              ],
            ),
          ),
        ),
      ),
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

class _MetaBlock extends StatelessWidget {
  const _MetaBlock({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: BookingTextStyles.metaLabel),
        const SizedBox(height: 8),
        Text(value, style: BookingTextStyles.metaValue),
      ],
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
      height: 64,
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
