import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/help_center_repository.dart';
import '../widgets/public_request_scaffold.dart';

class OtherQuestionsScreen extends StatefulWidget {
  const OtherQuestionsScreen({super.key, this.repository});
  final HelpCenterRepository? repository;
  @override
  State<OtherQuestionsScreen> createState() => _OtherQuestionsScreenState();
}

class _OtherQuestionsScreenState extends State<OtherQuestionsScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _gym = TextEditingController(),
      _subject = TextEditingController(),
      _message = TextEditingController();
  bool _working = false, _success = false;
  String? _error;
  HelpCenterRepository get repo =>
      widget.repository ??
      SupabaseHelpCenterRepository(Supabase.instance.client);
  @override
  void dispose() {
    for (final c in [_name, _email, _gym, _subject, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    String key,
    TextEditingController c,
    String label, {
    String? Function(String?)? validator,
    int lines = 1,
    int max = 200,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: c,
      validator: validator,
      maxLines: lines,
      maxLength: max,
      style: const TextStyle(color: Colors.white),
      decoration: publicFieldDecoration(label),
    ),
  );
  Future<void> submit() async {
    if (_working || !(_key.currentState?.validate() ?? false)) return;
    setState(() => _working = true);
    try {
      await repo.submitContact(
        ContactRequestInput(
          fullName: _name.text.trim(),
          email: _email.text.trim().toLowerCase(),
          gymName: _gym.text.trim().isEmpty ? null : _gym.text.trim(),
          subject: _subject.text.trim(),
          message: _message.text.trim(),
          locale: localeController.locale.languageCode,
        ),
      );
      if (mounted) setState(() => _success = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = appStrings.pick(
            "We couldn't send your request. Please try again.",
            'No pudimos enviar tu solicitud. Inténtalo de nuevo.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => PublicRequestScaffold(
    title: appStrings.pick('Other questions', 'Otras consultas'),
    onBack: context.pop,
    child: _success
        ? PublicRequestSuccess(
            body: appStrings.pick(
              "We've received your message.",
              'Hemos recibido tu mensaje.',
            ),
            onBack: () => context.go('/help'),
          )
        : Form(
            key: _key,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(
                    'contact-name',
                    _name,
                    '${appStrings.pick('Name', 'Nombre')} *',
                    validator: requiredPublic,
                  ),
                  field(
                    'contact-email',
                    _email,
                    'Email *',
                    validator: emailPublic,
                  ),
                  field(
                    'contact-gym',
                    _gym,
                    appStrings.pick('Gym name', 'Nombre del gimnasio'),
                  ),
                  field(
                    'contact-subject',
                    _subject,
                    '${appStrings.pick('Subject', 'Asunto')} *',
                    validator: requiredPublic,
                  ),
                  field(
                    'contact-message',
                    _message,
                    '${appStrings.pick('Message', 'Mensaje')} *',
                    validator: (v) {
                      final r = requiredPublic(v);
                      if (r != null) return r;
                      return v!.trim().length < 10
                          ? appStrings.pick(
                              'Add a little more detail.',
                              'Añade un poco más de detalle.',
                            )
                          : null;
                    },
                    lines: 6,
                    max: 4000,
                  ),
                  Text(
                    appStrings.pick(
                      "We'll only use your details to respond to your request.",
                      'Usaremos tus datos únicamente para responder a tu solicitud.',
                    ),
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const ValueKey('contact-error'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  const SizedBox(height: 16),
                  AppFormSubmitButton(
                    key: const ValueKey('contact-submit'),
                    label: appStrings.pick('SEND REQUEST', 'ENVIAR SOLICITUD'),
                    loading: _working,
                    enabled: !_working,
                    accentColor: AppColors.primary,
                    onPressed: submit,
                  ),
                ],
              ),
            ),
          ),
  );
}
