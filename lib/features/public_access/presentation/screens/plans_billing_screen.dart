import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../data/help_center_repository.dart';
import '../widgets/public_request_scaffold.dart';

class PlansBillingScreen extends StatelessWidget {
  const PlansBillingScreen({super.key, this.repository});
  final HelpCenterRepository? repository;

  @override
  Widget build(BuildContext context) => PublicRequestScaffold(
    title: appStrings.pick('Plans & billing', 'Planes y facturación'),
    onBack: context.pop,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenX),
        child: Text(
          appStrings.pick(
            'This section is under development.',
            'Esta sección está en desarrollo.',
          ),
          key: const ValueKey('plans-under-development'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 17),
        ),
      ),
    ),
  );
}
