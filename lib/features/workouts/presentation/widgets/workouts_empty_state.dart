import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'workout_text_styles.dart';

class WorkoutsEmptyState extends StatelessWidget {
  const WorkoutsEmptyState({super.key});

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
                  Icons.fitness_center_rounded,
                  color: Color(0xFFB59B6A),
                  size: 34,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                appStrings.workoutsNoToday,
                textAlign: TextAlign.center,
                style: WorkoutTextStyles.emptyTitle,
              ),
              const SizedBox(height: 8),
              Text(
                appStrings.workoutNeedProgram,
                textAlign: TextAlign.center,
                style: WorkoutTextStyles.emptyMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
