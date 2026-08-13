import 'package:flutter/material.dart';

import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../workout_colors.dart';

class WorkoutsLoadingState extends StatelessWidget {
  const WorkoutsLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppCenteredLoadingIndicator(color: WorkoutColors.primary);
  }
}
