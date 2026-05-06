import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'workout_text_styles.dart';

class WorkoutsLoadingState extends StatelessWidget {
  const WorkoutsLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFFB59B6A),
            ),
          ),
          const SizedBox(height: 16),
          Text(appStrings.workoutsTitle, style: WorkoutTextStyles.emptyMessage),
        ],
      ),
    );
  }
}
