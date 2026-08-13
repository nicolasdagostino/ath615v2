import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_main_header.dart';

class WorkoutsHeader extends StatelessWidget {
  const WorkoutsHeader({
    super.key,
    required this.gymName,
    required this.canManage,
    required this.onPrograms,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final String? gymName;
  final bool canManage;
  final VoidCallback onPrograms;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) => AppMainHeader(
    gymName: gymName ?? appStrings.appBrand,
    title: appStrings.workoutsTitle,
    unreadNotifications: unreadNotifications,
    onOpenNotifications: onOpenNotifications,
    leadingAction: canManage
        ? AppHeaderIconButton(icon: Icons.grid_view_rounded, onTap: onPrograms)
        : null,
  );
}
