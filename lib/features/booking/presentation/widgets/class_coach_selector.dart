import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
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
  });

  final List<ClassCoachOption> coaches;
  final String? selectedCoachId;
  final bool loading;
  final Object? error;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRetry;
  final String? currentCoachId;
  final String? currentCoachName;

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
        icon: const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
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
          style: GoogleFonts.barlow(
            color: AppColors.textPrimary(context),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            labelText: appStrings.coachFieldLabel,
            labelStyle: GoogleFonts.barlow(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: const Icon(
              Icons.sports_outlined,
              color: AppColors.accent,
            ),
            filled: true,
            fillColor: AppColors.surface(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.input),
              borderSide: BorderSide(color: AppColors.border(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.input),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
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
            style: GoogleFonts.barlow(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
        ],
        if (unavailableId != null) ...[
          const SizedBox(height: 8),
          Text(
            appStrings.currentCoachUnavailable,
            key: const Key('class-coach-unavailable'),
            style: GoogleFonts.barlow(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
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
              style: GoogleFonts.barlow(
                color: AppColors.textPrimary(context),
                fontSize: 14,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
