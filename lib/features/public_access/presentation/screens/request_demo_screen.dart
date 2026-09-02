import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_system_ui.dart';
import '../../../../core/widgets/app_detail_header.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/demo_request_repository.dart';

class RequestDemoScreen extends StatefulWidget {
  const RequestDemoScreen({super.key, this.repository});
  final DemoRequestRepository? repository;

  @override
  State<RequestDemoScreen> createState() => _RequestDemoScreenState();
}

class _RequestDemoScreenState extends State<RequestDemoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _gym = TextEditingController();
  final _members = TextEditingController();
  final _message = TextEditingController();
  bool _submitting = false;
  bool _success = false;
  String? _error;

  DemoRequestRepository get _repository =>
      widget.repository ??
      SupabaseDemoRequestRepository(Supabase.instance.client);

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _gym,
      _members,
      _message,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      (value?.trim().isEmpty ?? true) ? appStrings.demoRequiredError : null;

  String? _validEmail(String? value) {
    final required = _required(value);
    if (required != null) return required;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!.trim())
        ? null
        : appStrings.demoEmailError;
  }

  String? _validMembers(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final count = int.tryParse(text);
    return count != null && count >= 0 && count <= 1000000
        ? null
        : appStrings.demoMemberCountError;
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _repository.submit(
        DemoRequestInput(
          fullName: _name.text.trim(),
          email: _email.text.trim().toLowerCase(),
          phone: _optional(_phone),
          gymName: _gym.text.trim(),
          approxMemberCount: _members.text.trim().isEmpty
              ? null
              : int.parse(_members.text.trim()),
          message: _optional(_message),
          locale: localeController.locale.languageCode,
        ),
      );
      if (mounted) setState(() => _success = true);
    } catch (_) {
      if (mounted) setState(() => _error = appStrings.demoSendError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
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

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboard,
    int maxLength = 160,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: TextFormField(
      key: key,
      controller: controller,
      validator: validator,
      keyboardType: keyboard,
      maxLength: maxLength,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(label),
    ),
  );

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
            title: appStrings.requestDemo,
            onBack: context.pop,
            leadingColor: AppColors.primary,
          ),
          Expanded(
            child: _success
                ? _Success(onBack: () => context.go('/login'))
                : Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(AppSpacing.screenX),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            appStrings.demoHeadline,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            appStrings.demoDescription,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _field(
                            key: const ValueKey('demo-full-name'),
                            controller: _name,
                            label: '${appStrings.authFullName} *',
                            validator: _required,
                          ),
                          _field(
                            key: const ValueKey('demo-email'),
                            controller: _email,
                            label: '${appStrings.authEmail} *',
                            validator: _validEmail,
                            keyboard: TextInputType.emailAddress,
                          ),
                          _field(
                            key: const ValueKey('demo-phone'),
                            controller: _phone,
                            label: appStrings.authPhone,
                            keyboard: TextInputType.phone,
                            maxLength: 40,
                          ),
                          _field(
                            key: const ValueKey('demo-gym-name'),
                            controller: _gym,
                            label: '${appStrings.demoGymName} *',
                            validator: _required,
                          ),
                          _field(
                            key: const ValueKey('demo-member-count'),
                            controller: _members,
                            label: appStrings.demoMemberCount,
                            validator: _validMembers,
                            keyboard: TextInputType.number,
                            maxLength: 7,
                          ),
                          _field(
                            key: const ValueKey('demo-message'),
                            controller: _message,
                            label: appStrings.demoOptionalMessage,
                            maxLength: 1000,
                            maxLines: 4,
                          ),
                          Text(
                            appStrings.demoPrivacy,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: Text(
                                _error!,
                                key: const ValueKey('demo-error'),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.md),
                          AppFormSubmitButton(
                            key: const ValueKey('demo-submit'),
                            label: appStrings.demoSubmit,
                            loading: _submitting,
                            enabled: !_submitting,
                            accentColor: AppColors.primary,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      ),
    ),
  );
}

class _Success extends StatelessWidget {
  const _Success({required this.onBack});
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
          const SizedBox(height: AppSpacing.md),
          Text(
            appStrings.demoSuccessTitle,
            key: const ValueKey('demo-success'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            appStrings.demoSuccessBody,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: onBack,
            child: Text(appStrings.backToSignIn.toUpperCase()),
          ),
        ],
      ),
    ),
  );
}
