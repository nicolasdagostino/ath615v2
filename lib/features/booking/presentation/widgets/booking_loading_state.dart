
import 'package:flutter/material.dart';

class BookingLoadingState extends StatelessWidget {
  const BookingLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: const [
        _BookingSkeletonCard(compact: true),
        SizedBox(height: 18),
        _BookingSkeletonCard(),
        SizedBox(height: 18),
        _BookingSkeletonCard(),
      ],
    );
  }
}

class _BookingSkeletonCard extends StatelessWidget {
  const _BookingSkeletonCard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: compact
          ? Row(
              children: const [
                _SkeletonBox(width: 54, height: 54, radius: 18),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBox(width: double.infinity, height: 18, radius: 999),
                      SizedBox(height: 12),
                      _SkeletonBox(width: 170, height: 14, radius: 999),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonBox(width: 130, height: 14, radius: 999),
                SizedBox(height: 18),
                _SkeletonBox(width: double.infinity, height: 42, radius: 14),
                SizedBox(height: 16),
                _SkeletonBox(width: 220, height: 16, radius: 999),
                SizedBox(height: 28),
                _SkeletonBox(width: double.infinity, height: 150, radius: 24),
                SizedBox(height: 22),
                _SkeletonBox(width: double.infinity, height: 16, radius: 999),
                SizedBox(height: 12),
                _SkeletonBox(width: 260, height: 16, radius: 999),
              ],
            ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF0),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
