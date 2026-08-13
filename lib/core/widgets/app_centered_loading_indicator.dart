import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';

class AppCenteredLoadingIndicator extends StatelessWidget {
  const AppCenteredLoadingIndicator({
    super.key,
    this.color = AppColors.primary,
  });

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: appStrings.pick('Loading', 'Cargando'),
      child: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(
          key: const ValueKey('app-centered-loading-indicator'),
          strokeWidth: 2.2,
          color: color,
        ),
      ),
    ),
  );
}
