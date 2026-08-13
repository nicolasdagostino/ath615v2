import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../booking_colors.dart';

class BookingClassFormScaffold extends StatelessWidget {
  const BookingClassFormScaffold({
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: Column(
      children: [
        BookingClassFormHeader(title: title, onClose: onClose),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenX,
              AppSpacing.md,
              AppSpacing.screenX,
              AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: children,
          ),
        ),
      ],
    ),
    bottomNavigationBar: BookingClassBottomAction(child: submit),
  );
}

class BookingClassFormHeader extends StatelessWidget {
  const BookingClassFormHeader({
    super.key,
    required this.title,
    required this.onClose,
  });

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey('booking-class-form-header'),
    child: AppFormHeader(
      title: title,
      onClose: onClose,
      accentColor: BookingColors.primary,
      closeKey: const ValueKey('booking-class-form-close'),
    ),
  );
}

class BookingClassSectionLabel extends StatelessWidget {
  const BookingClassSectionLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => AppFormSectionLabel(label: label);
}

InputDecoration bookingClassInput(
  BuildContext context, {
  required IconData icon,
  String hintText = '',
  String? suffix,
}) {
  return appFormInput(
    context,
    accentColor: BookingColors.primary,
    icon: icon,
    hintText: hintText,
    suffix: suffix,
  );
}

class BookingClassPickerField extends StatelessWidget {
  const BookingClassPickerField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool placeholder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      BookingClassSectionLabel(label: label.toUpperCase()),
      const SizedBox(height: AppSpacing.xs),
      AppFormActionField(
        icon: icon,
        value: value,
        onTap: onTap,
        accentColor: BookingColors.primary,
        placeholder: placeholder,
        trailing: false,
      ),
    ],
  );
}

class BookingClassSubmitButton extends StatelessWidget {
  const BookingClassSubmitButton({
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
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey('booking-class-form-submit'),
    child: AppFormSubmitButton(
      label: label,
      loading: loading,
      enabled: enabled,
      onPressed: onPressed,
      accentColor: BookingColors.primary,
    ),
  );
}

class BookingClassBottomAction extends StatelessWidget {
  const BookingClassBottomAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        AppSpacing.sm,
        AppSpacing.screenX,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        border: Border(
          top: BorderSide(color: AppColors.border(context), width: 0.8),
        ),
      ),
      child: child,
    ),
  );
}
