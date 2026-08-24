import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_control_styles.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../workout_colors.dart';

InputDecoration workoutFormInput(
  BuildContext context, {
  required String hintText,
  required IconData icon,
}) {
  return appFormInput(
    context,
    icon: icon,
    accentColor: WorkoutColors.primary,
    hintText: hintText,
  );
}

InputDecoration workoutDescriptionInput(
  BuildContext context, {
  required String hintText,
  Widget? prefixIcon,
}) {
  return AppControlStyles.input(
    context,
    hintText: hintText,
    prefixIcon: prefixIcon,
  ).copyWith(
    alignLabelWithHint: true,
    fillColor: AppColors.surface(context),
    hintStyle: appFormPlaceholderStyle(context),
    contentPadding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: const BorderSide(color: WorkoutColors.primary, width: 1.2),
    ),
  );
}

class WorkoutFormSectionLabel extends StatelessWidget {
  const WorkoutFormSectionLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return AppFormSectionLabel(label: label);
  }
}

class WorkoutFormActionRow extends StatelessWidget {
  const WorkoutFormActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFormActionField(
      icon: icon,
      value: title,
      onTap: onTap,
      accentColor: WorkoutColors.primary,
    );
  }
}

class WorkoutFormButton extends StatelessWidget {
  const WorkoutFormButton({
    super.key,
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('workout-form-submit'),
      child: AppFormSubmitButton(
        label: label,
        loading: loading,
        enabled: enabled,
        onPressed: onPressed,
        accentColor: WorkoutColors.primary,
      ),
    );
  }
}

class WorkoutFormScaffold extends StatelessWidget {
  const WorkoutFormScaffold({
    super.key,
    required this.title,
    required this.onClose,
    required this.children,
    required this.submit,
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  final Widget submit;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return _WorkoutFormKeyboardState(
      visible: keyboardVisible,
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        body: Column(
          children: [
            WorkoutFormHeader(title: title, onClose: onClose),
            Expanded(
              child: ListView(
                key: const ValueKey('workout-form-scroll'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenX,
                  AppSpacing.md,
                  AppSpacing.screenX,
                  keyboardVisible ? AppSpacing.md : AppSpacing.xl,
                ),
                children: children,
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenX,
              keyboardVisible ? AppSpacing.xxs : AppSpacing.sm,
              AppSpacing.screenX,
              keyboardVisible ? AppSpacing.xs : AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              border: Border(
                top: BorderSide(color: AppColors.border(context), width: 0.8),
              ),
            ),
            child: submit,
          ),
        ),
      ),
    );
  }
}

class WorkoutFormHeader extends StatelessWidget {
  const WorkoutFormHeader({
    super.key,
    required this.title,
    required this.onClose,
  });

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey('workout-form-header'),
    child: AppFormHeader(
      title: title,
      onClose: onClose,
      accentColor: WorkoutColors.primary,
      closeKey: const ValueKey('workout-form-close'),
    ),
  );
}

class WorkoutFormFields extends StatelessWidget {
  const WorkoutFormFields({
    super.key,
    required this.loadingPrograms,
    required this.programs,
    required this.programId,
    required this.onProgramChanged,
    required this.dateLabel,
    required this.onDateTap,
    required this.imageTitle,
    required this.imageSubtitle,
    required this.onImageTap,
    required this.descriptionController,
    this.imagePreview,
    this.onRemoveImage,
  });

  final bool loadingPrograms;
  final List<Map<String, dynamic>> programs;
  final String? programId;
  final ValueChanged<String?> onProgramChanged;
  final String dateLabel;
  final VoidCallback onDateTap;
  final String imageTitle;
  final String imageSubtitle;
  final VoidCallback onImageTap;
  final TextEditingController descriptionController;
  final Widget? imagePreview;
  final VoidCallback? onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = _WorkoutFormKeyboardState.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkoutFormSectionLabel(label: appStrings.workoutProgram.toUpperCase()),
        const SizedBox(height: AppSpacing.xs),
        if (loadingPrograms)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: WorkoutColors.primary),
            ),
          )
        else if (programs.isEmpty)
          Text(
            appStrings.workoutNeedProgram,
            style: AppTypography.body(context),
          )
        else
          DropdownButtonFormField<String>(
            key: const ValueKey('workout-program-field'),
            initialValue: programId,
            isExpanded: true,
            dropdownColor: AppColors.surface(context),
            iconEnabledColor: AppColors.textSecondary(context),
            style: appFormValueStyle(context),
            decoration: workoutFormInput(
              context,
              hintText: appStrings.workoutProgram,
              icon: Icons.fitness_center_outlined,
            ),
            items: programs
                .map(
                  (program) => DropdownMenuItem<String>(
                    value: program['id'].toString(),
                    child: Text(
                      program['name']?.toString() ?? appStrings.workoutProgram,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: onProgramChanged,
          ),
        const SizedBox(height: AppSpacing.lg),
        WorkoutFormSectionLabel(label: appStrings.workoutDate.toUpperCase()),
        const SizedBox(height: AppSpacing.xs),
        WorkoutFormActionRow(
          key: const ValueKey('workout-date-field'),
          icon: Icons.calendar_month_outlined,
          title: dateLabel,
          subtitle: '',
          onTap: onDateTap,
        ),
        const SizedBox(height: AppSpacing.lg),
        WorkoutFormSectionLabel(label: appStrings.workoutImage.toUpperCase()),
        const SizedBox(height: AppSpacing.xs),
        WorkoutFormActionRow(
          key: const ValueKey('workout-image-field'),
          icon: Icons.image_outlined,
          title: imageTitle,
          subtitle: imageSubtitle,
          onTap: onImageTap,
        ),
        if (imagePreview != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.input),
            child: imagePreview!,
          ),
          if (onRemoveImage != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('workout-remove-image'),
                onPressed: onRemoveImage,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                label: Text(appStrings.removeImage.toUpperCase()),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  textStyle: AppTypography.buttonLabel(context),
                  minimumSize: const Size(
                    AppSizes.minimumTouchTarget,
                    AppSizes.minimumTouchTarget,
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        WorkoutFormSectionLabel(
          label: appStrings.workoutDescription.toUpperCase(),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          key: const ValueKey('workout-content-field'),
          controller: descriptionController,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          minLines: keyboardVisible ? 12 : 10,
          maxLines: keyboardVisible ? 16 : 18,
          scrollPadding: EdgeInsets.only(
            bottom: keyboardVisible ? 76 : AppSpacing.xl,
          ),
          keyboardType: TextInputType.multiline,
          style: appFormValueStyle(context),
          decoration: workoutDescriptionInput(
            context,
            hintText: appStrings.workoutWriteWod,
          ),
        ),
      ],
    );
  }
}

class _WorkoutFormKeyboardState extends InheritedWidget {
  const _WorkoutFormKeyboardState({
    required this.visible,
    required super.child,
  });

  final bool visible;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_WorkoutFormKeyboardState>()
          ?.visible ??
      false;

  @override
  bool updateShouldNotify(_WorkoutFormKeyboardState oldWidget) =>
      oldWidget.visible != visible;
}
