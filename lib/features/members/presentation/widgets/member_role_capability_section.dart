import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';

class MemberRoleCapabilitySection extends StatelessWidget {
  const MemberRoleCapabilitySection({
    super.key,
    required this.role,
    required this.isCoach,
    required this.isUpdatingCoach,
    required this.onRoleSelected,
    required this.onCoachChanged,
  });

  final String role;
  final bool isCoach;
  final bool isUpdatingCoach;
  final ValueChanged<String> onRoleSelected;
  final ValueChanged<bool> onCoachChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isLegacyCoach = role == 'coach';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appStrings.role.toUpperCase(),
          style: textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RoleChoice(
              label: appStrings.athleteRole,
              selected: role == 'athlete',
              enabled: !isUpdatingCoach,
              onSelected: () => onRoleSelected('athlete'),
            ),
            _RoleChoice(
              label: appStrings.coach,
              selected: isLegacyCoach,
              enabled: !isUpdatingCoach,
              onSelected: () => onRoleSelected('coach'),
            ),
            _RoleChoice(
              label: appStrings.adminRole,
              selected: role == 'admin',
              enabled: !isUpdatingCoach,
              onSelected: () => onRoleSelected('admin'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: SwitchListTile.adaptive(
            key: const Key('member-coach-capability-switch'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            title: Text(
              appStrings.coachCapability,
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              isLegacyCoach
                  ? appStrings.legacyCoachCapabilityDescription
                  : appStrings.coachCapabilityDescription,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary(context),
                height: 1.35,
              ),
            ),
            value: isCoach,
            onChanged: isUpdatingCoach || isLegacyCoach ? null : onCoachChanged,
          ),
        ),
      ],
    );
  }
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: ChoiceChip(
        label: Text(label.toUpperCase()),
        selected: selected,
        onSelected: enabled ? (_) => onSelected() : null,
        selectedColor: AppColors.primary.withValues(alpha: 0.12),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border(context),
        ),
        labelStyle: TextStyle(
          color: selected
              ? AppColors.textPrimary(context)
              : AppColors.textSecondary(context),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
