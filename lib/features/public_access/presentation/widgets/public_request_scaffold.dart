import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_system_ui.dart';
import '../../../../core/widgets/app_detail_header.dart';

class PublicRequestScaffold extends StatelessWidget {
  const PublicRequestScaffold({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
  });
  final String title;
  final VoidCallback onBack;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: darkScreenSystemUiOverlayStyle,
    child: Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            AppDetailHeader(
              title: title,
              onBack: onBack,
              leadingColor: AppColors.primary,
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

InputDecoration publicFieldDecoration(String label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(color: Colors.white70),
  filled: true,
  fillColor: const Color(0xFF171717),
  enabledBorder: OutlineInputBorder(
    borderSide: const BorderSide(color: Color(0xFF444444)),
    borderRadius: BorderRadius.circular(12),
  ),
  focusedBorder: OutlineInputBorder(
    borderSide: const BorderSide(color: AppColors.primary),
    borderRadius: BorderRadius.circular(12),
  ),
  errorBorder: OutlineInputBorder(
    borderSide: const BorderSide(color: AppColors.danger),
    borderRadius: BorderRadius.circular(12),
  ),
);
String? requiredPublic(String? value) => value?.trim().isEmpty ?? true
    ? appStrings.pick('Required field', 'Campo obligatorio')
    : null;
String? emailPublic(String? value) {
  final r = requiredPublic(value);
  if (r != null) return r;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!.trim())
      ? null
      : appStrings.pick('Enter a valid email', 'Introduce un email válido');
}

class PublicRequestSuccess extends StatelessWidget {
  const PublicRequestSuccess({
    super.key,
    required this.body,
    required this.onBack,
  });
  final String body;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.screenX),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.primary,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            appStrings.pick('Request sent', 'Solicitud enviada'),
            key: const ValueKey('request-success'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onBack,
            child: Text(appStrings.pick('BACK TO HELP', 'VOLVER A AYUDA')),
          ),
        ],
      ),
    ),
  );
}
