import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/help_center_repository.dart';
import '../widgets/public_request_scaffold.dart';

class TechnicalSupportScreen extends StatefulWidget {
  const TechnicalSupportScreen({super.key, this.repository, this.picker});
  final HelpCenterRepository? repository;
  final ImagePicker? picker;
  @override
  State<TechnicalSupportScreen> createState() => _TechnicalSupportScreenState();
}

class _TechnicalSupportScreenState extends State<TechnicalSupportScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _gym = TextEditingController(),
      _screen = TextEditingController(),
      _description = TextEditingController();
  String _type = 'login';
  XFile? _attachment;
  bool _working = false, _success = false;
  String? _error;
  HelpCenterRepository get repo =>
      widget.repository ??
      SupabaseHelpCenterRepository(Supabase.instance.client);
  static const types = [
    'login',
    'booking',
    'memberships',
    'workouts',
    'notifications',
    'profile',
    'administration',
    'other',
  ];
  String label(String t) => switch (t) {
    'login' => appStrings.pick('Login', 'Inicio de sesión'),
    'booking' => appStrings.pick('Bookings', 'Reservas'),
    'memberships' => appStrings.pick('Memberships', 'Membresías'),
    'workouts' => appStrings.pick('Workouts / WOD', 'Entrenamientos / WOD'),
    'notifications' => appStrings.pick('Notifications', 'Notificaciones'),
    'profile' => appStrings.pick('Profile', 'Perfil'),
    'administration' => appStrings.pick('Administration', 'Administración'),
    _ => appStrings.pick('Other', 'Otro'),
  };
  @override
  void dispose() {
    for (final c in [_name, _email, _gym, _screen, _description]) {
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
    int max = 160,
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
  Future<void> pick() async {
    final f = await (widget.picker ?? ImagePicker()).pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    final ext = f.name.toLowerCase();
    if (bytes.length > 5 * 1024 * 1024 ||
        !(ext.endsWith('.png') ||
            ext.endsWith('.jpg') ||
            ext.endsWith('.jpeg') ||
            ext.endsWith('.webp'))) {
      if (mounted) {
        setState(
          () => _error = appStrings.pick(
            'Use one PNG, JPEG or WebP image up to 5 MB.',
            'Usa una imagen PNG, JPEG o WebP de hasta 5 MB.',
          ),
        );
      }
      return;
    }
    setState(() => _attachment = f);
  }

  Future<void> submit() async {
    if (_working || !(_key.currentState?.validate() ?? false)) return;
    setState(() => _working = true);
    try {
      List<int>? bytes;
      String? mime;
      if (_attachment != null) {
        bytes = await _attachment!.readAsBytes();
        final n = _attachment!.name.toLowerCase();
        mime = n.endsWith('.png')
            ? 'image/png'
            : n.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
      }
      await repo.submitSupport(
        SupportRequestInput(
          fullName: _name.text.trim(),
          email: _email.text.trim().toLowerCase(),
          gymName: _gym.text.trim().isEmpty ? null : _gym.text.trim(),
          issueType: _type,
          screenName: _screen.text.trim().isEmpty ? null : _screen.text.trim(),
          description: _description.text.trim(),
          locale: localeController.locale.languageCode,
          attachmentBytes: bytes,
          attachmentMime: mime,
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
    title: appStrings.pick('Technical support', 'Soporte técnico'),
    onBack: context.pop,
    child: _success
        ? PublicRequestSuccess(
            body: appStrings.pick(
              "We've received your support request.",
              'Hemos recibido tu solicitud de soporte.',
            ),
            onBack: () => context.go('/help'),
          )
        : Form(
            key: _key,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpacing.screenX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    appStrings.pick(
                      "Tell us what happened and we'll help you resolve it.",
                      'Cuéntanos qué ocurrió y te ayudaremos a resolverlo.',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  field(
                    'support-name',
                    _name,
                    '${appStrings.pick('Name', 'Nombre')} *',
                    validator: requiredPublic,
                  ),
                  field(
                    'support-email',
                    _email,
                    'Email *',
                    validator: emailPublic,
                  ),
                  field(
                    'support-gym',
                    _gym,
                    appStrings.pick('Gym name', 'Nombre del gimnasio'),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('support-issue-type'),
                    initialValue: _type,
                    dropdownColor: const Color(0xFF171717),
                    decoration: publicFieldDecoration(
                      '${appStrings.pick('Issue type', 'Tipo de problema')} *',
                    ),
                    items: types
                        .map(
                          (t) =>
                              DropdownMenuItem(value: t, child: Text(label(t))),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                  const SizedBox(height: 12),
                  field(
                    'support-screen',
                    _screen,
                    appStrings.pick(
                      'Where did it happen?',
                      '¿En qué pantalla ocurrió?',
                    ),
                  ),
                  field(
                    'support-description',
                    _description,
                    '${appStrings.pick('Description', 'Descripción')} *',
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
                    lines: 5,
                    max: 4000,
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('support-attachment'),
                    onPressed: pick,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _attachment?.name ??
                          appStrings.pick(
                            'Add screenshot (optional)',
                            'Añadir captura (opcional)',
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appStrings.pick(
                      'Do not include passwords or sensitive information in the screenshot.',
                      'No incluyas contraseñas ni información sensible en la captura.',
                    ),
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appStrings.pick(
                      "We'll only use your details to respond to your request.",
                      'Usaremos tus datos únicamente para responder a tu solicitud.',
                    ),
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        key: const ValueKey('support-error'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  const SizedBox(height: 16),
                  AppFormSubmitButton(
                    key: const ValueKey('support-submit'),
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
