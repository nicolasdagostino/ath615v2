import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_control_styles.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../domain/class_coach.dart';

class ClassCoachSelector extends StatelessWidget {
  const ClassCoachSelector({
    super.key,
    required this.coaches,
    required this.selectedCoachId,
    required this.loading,
    required this.error,
    required this.onChanged,
    required this.onRetry,
    this.currentCoachId,
    this.currentCoachName,
    this.accentColor = AppColors.accent,
  });

  final List<ClassCoachOption> coaches;
  final String? selectedCoachId;
  final bool loading;
  final Object? error;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRetry;
  final String? currentCoachId;
  final String? currentCoachName;
  final Color accentColor;

  bool get _currentCoachUnavailable {
    final id = currentCoachId;
    return id != null &&
        id.isNotEmpty &&
        coaches.every((coach) => coach.id != id);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _SelectorMessage(
        key: const Key('class-coach-loading'),
        icon: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
        ),
        message: appStrings.loadingCoaches,
      );
    }

    if (error != null) {
      return _SelectorMessage(
        key: const Key('class-coach-error'),
        icon: const Icon(Icons.error_outline, color: AppColors.danger),
        message: appStrings.coachesLoadError,
        action: TextButton(onPressed: onRetry, child: Text(appStrings.retry)),
      );
    }

    final unavailableId = _currentCoachUnavailable ? currentCoachId : null;
    final unavailableName = currentCoachName?.trim().isNotEmpty == true
        ? currentCoachName!.trim()
        : appStrings.currentCoach;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
            'class-coach-${selectedCoachId ?? 'none'}-${coaches.length}-$unavailableId',
          ),
          initialValue: selectedCoachId ?? '',
          isExpanded: true,
          dropdownColor: AppColors.surface(context),
          iconEnabledColor: AppColors.textSecondary(context),
          style: appFormValueStyle(context),
          decoration:
              AppControlStyles.input(
                context,
                hintText: appStrings.coachFieldLabel,
                prefixIcon: const Icon(
                  Icons.sports_outlined,
                  color: AppColors.accent,
                ),
              ).copyWith(
                fillColor: AppColors.surface(context),
                prefixIcon: Icon(Icons.sports_outlined, color: accentColor),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  borderSide: BorderSide(color: accentColor, width: 1.2),
                ),
              ),
          items: [
            DropdownMenuItem<String>(
              value: '',
              child: Text(appStrings.noCoach),
            ),
            ...coaches.map(
              (coach) => DropdownMenuItem<String>(
                value: coach.id,
                child: Text(
                  coach.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (unavailableId != null)
              DropdownMenuItem<String>(
                value: unavailableId,
                enabled: false,
                child: Text(
                  '$unavailableName · ${appStrings.notAvailableForNewClasses}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) =>
              onChanged(value == null || value.isEmpty ? null : value),
        ),
        if (coaches.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            appStrings.noCoachesAvailable,
            key: const Key('class-coach-empty'),
            style: AppTypography.helper(context),
          ),
        ],
        if (unavailableId != null) ...[
          const SizedBox(height: 8),
          Text(
            appStrings.currentCoachUnavailable,
            key: const Key('class-coach-unavailable'),
            style: AppTypography.helper(context),
          ),
        ],
      ],
    );
  }
}

class _SelectorMessage extends StatelessWidget {
  const _SelectorMessage({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final Widget icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.body(context).copyWith(fontSize: 14),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
