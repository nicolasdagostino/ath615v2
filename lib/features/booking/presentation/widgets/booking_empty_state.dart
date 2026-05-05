import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';

class BookingEmptyState extends StatelessWidget {
  const BookingEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 34, 24, 34),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F3EA),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.event_busy_rounded,
                  color: Color(0xFFB59B6A),
                  size: 34,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                appStrings.bookingEmptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF111318),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appStrings.bookingEmptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8F96A3),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
