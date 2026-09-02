import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_detail_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const bool stripeConnectSetupEnabled = true;

int saasPlanCapacityShortfall({required int active, required int? limit}) =>
    limit == null ? 0 : (active - limit).clamp(0, active);

String saasPlanChangeErrorMessage(Object error) {
  final value = error.toString();
  if (value.contains('saas_plan_capacity_too_low')) {
    return appStrings.pick(
      'This plan does not have enough capacity for your active athletes.',
      'Este plan no tiene capacidad suficiente para tus atletas activos.',
    );
  }
  if (value.contains('saas_plan_change_pending')) {
    return appStrings.pick(
      'There is already a plan change awaiting review.',
      'Ya existe un cambio de plan pendiente de revisión.',
    );
  }
  if (value.contains('saas_plan_unchanged')) {
    return appStrings.pick(
      'This is your current plan.',
      'Este es tu plan actual.',
    );
  }
  return appStrings.pick(
    'The plan change request could not be completed.',
    'No se pudo completar la solicitud de cambio de plan.',
  );
}

enum GymStripeConnectState {
  disconnected,
  setupPending,
  chargesDisabled,
  paymentsEnabled,
}

enum StripeConnectRouteAction { returnAndRefresh, refreshOnboarding }

StripeConnectRouteAction? parseStripeConnectRouteAction(String? value) =>
    switch (value) {
      'return' => StripeConnectRouteAction.returnAndRefresh,
      'refresh' => StripeConnectRouteAction.refreshOnboarding,
      _ => null,
    };

GymStripeConnectState gymStripeConnectState({
  required String? accountId,
  required bool onboardingComplete,
  required bool chargesEnabled,
  required bool payoutsEnabled,
}) {
  if (accountId == null || accountId.trim().isEmpty) {
    return GymStripeConnectState.disconnected;
  }
  if (!onboardingComplete || !payoutsEnabled) {
    return GymStripeConnectState.setupPending;
  }
  if (!chargesEnabled) return GymStripeConnectState.chargesDisabled;
  return GymStripeConnectState.paymentsEnabled;
}

class GymSettingsScreen extends StatefulWidget {
  const GymSettingsScreen({
    super.key,
    this.gymLoaderForTesting,
    this.connectAction,
    this.statusRefresherForTesting,
    this.onboardingOpenerForTesting,
  });

  final Future<Map<String, dynamic>?> Function()? gymLoaderForTesting;
  final StripeConnectRouteAction? connectAction;

  @visibleForTesting
  final Future<void> Function()? statusRefresherForTesting;

  @visibleForTesting
  final Future<void> Function()? onboardingOpenerForTesting;

  @override
  State<GymSettingsScreen> createState() => _GymSettingsScreenState();
}

class _GymSettingsScreenState extends State<GymSettingsScreen>
    with WidgetsBindingObserver {
  final _business = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();

  String? _gymId;
  String? _gymCode;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _connectingStripe = false;
  String? _stripeAccountId;
  bool _stripeOnboardingComplete = false;
  bool _stripeChargesEnabled = false;
  bool _stripePayoutsEnabled = false;
  String? _logoUrl;
  Map<String, dynamic>? _saasUsage;
  List<Map<String, dynamic>> _saasPlans = const [];
  Map<String, dynamic>? _pendingSaasRequest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadGym();
    if (!mounted) return;
    switch (widget.connectAction) {
      case StripeConnectRouteAction.returnAndRefresh:
        await _refreshStripeStatus();
        break;
      case StripeConnectRouteAction.refreshOnboarding:
        await _connectStripe();
        break;
      case null:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (stripeConnectSetupEnabled && state == AppLifecycleState.resumed) {
      _refreshStripeStatus();
    }
  }

  Future<void> _loadGym() async {
    final injected = widget.gymLoaderForTesting;
    if (injected != null) {
      final gym = await injected();
      _applyGym(gym);
      if (mounted) setState(() => _loading = false);
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final effectiveGymId = await Supabase.instance.client.rpc(
      'effective_gym_id',
    );
    _gymId = effectiveGymId?.toString();

    if (_gymId != null) {
      final gym = await Supabase.instance.client
          .from('gyms')
          .select(
            'business_name,phone,email,website,address,name,logo_url,gym_code,'
            'stripe_account_id,stripe_onboarding_complete,'
            'stripe_charges_enabled,stripe_payouts_enabled',
          )
          .eq('id', _gymId!)
          .single();

      _applyGym(gym);
      final usageRows = await Supabase.instance.client.rpc(
        'get_effective_gym_saas_usage',
      );
      final rows = List<Map<String, dynamic>>.from(usageRows as List);
      _saasUsage = rows.isEmpty ? null : rows.first;
      _saasPlans = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('saas_plans')
            .select('code,name,active_member_limit,monthly_price_eur')
            .eq('is_active', true)
            .order('sort_order'),
      );
      final pendingRows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client.rpc(
              'get_effective_gym_pending_saas_plan_change',
            )
            as List,
      );
      _pendingSaasRequest = pendingRows.firstOrNull;
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _requestSaasPlan(Map<String, dynamic> plan) async {
    try {
      final request = await Supabase.instance.client.rpc(
        'request_effective_gym_saas_plan_change',
        params: {'p_requested_plan_code': plan['code']},
      );
      if (!mounted) return;
      setState(() => _pendingSaasRequest = Map<String, dynamic>.from(request));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saasPlanChangeErrorMessage(error))),
      );
    }
  }

  Future<void> _cancelSaasRequest() async {
    final request = _pendingSaasRequest;
    if (request == null) return;
    try {
      await Supabase.instance.client.rpc(
        'cancel_effective_gym_saas_plan_change',
        params: {'p_request_id': request['id']},
      );
      if (mounted) {
        setState(() => _pendingSaasRequest = null);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(saasPlanChangeErrorMessage(error))),
        );
      }
    }
  }

  Future<void> _showSaasPlans() => showDialog<void>(
    context: context,
    builder: (c) {
      final active =
          (_saasUsage?['active_athlete_count'] as num?)?.toInt() ?? 0;
      final currentCode = _saasUsage?['plan_code']?.toString();
      final pending = _pendingSaasRequest;
      return AlertDialog(
        title: Text(appStrings.pick('YOUR PLAN', 'TU PLAN')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_saasUsage?['plan_name'] ?? 'FREE'} · €${_saasPlans.where((p) => p['code'] == currentCode).firstOrNull?['monthly_price_eur'] ?? 0} / ${appStrings.pick('month', 'mes')}',
                  key: const ValueKey('saas-current-plan-detail'),
                  style: AppTypography.sectionTitle(context),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _saasUsage?['active_member_limit'] == null
                      ? '$active ${appStrings.pick('active athletes · Unlimited', 'atletas activos · Sin límite')}'
                      : '$active ${appStrings.pick('of', 'de')} ${_saasUsage?['active_member_limit']} ${appStrings.pick('active athletes', 'atletas activos')} · ${_saasUsage?['remaining_slots']} ${appStrings.pick('spots available', 'plazas disponibles')}',
                ),
                const SizedBox(height: AppSpacing.md),
                if (pending != null) ...[
                  Text(
                    '${appStrings.pick('CHANGE REQUESTED', 'CAMBIO SOLICITADO')}\n${pending['current_plan_code'].toString().toUpperCase()} → ${pending['requested_plan_code'].toString().toUpperCase()}\n${appStrings.pick('Pending approval', 'Pendiente de aprobación')}',
                    key: const ValueKey('saas-pending-change'),
                  ),
                  TextButton(
                    onPressed: _cancelSaasRequest,
                    child: Text(
                      appStrings.pick('CANCEL REQUEST', 'CANCELAR SOLICITUD'),
                    ),
                  ),
                ] else
                  ..._saasPlans.map((plan) {
                    final limit = (plan['active_member_limit'] as num?)
                        ?.toInt();
                    final shortfall = saasPlanCapacityShortfall(
                      active: active,
                      limit: limit,
                    );
                    final isCurrent = plan['code'] == currentCode;
                    return Padding(
                      key: ValueKey('saas-plan-${plan['code']}'),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${plan['name']} · €${plan['monthly_price_eur']} / ${appStrings.pick('month', 'mes')}',
                          ),
                          Text(
                            limit == null
                                ? appStrings.pick(
                                    'Unlimited athletes',
                                    'Atletas ilimitados',
                                  )
                                : shortfall == 0
                                ? appStrings.pick(
                                    'Up to $limit athletes',
                                    'Hasta $limit atletas',
                                  )
                                : appStrings.pick(
                                    'Deactivate at least $shortfall athletes before requesting this plan.',
                                    'Debes desactivar al menos $shortfall atletas antes de solicitar este plan.',
                                  ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: isCurrent || shortfall > 0
                                  ? null
                                  : () => _requestSaasPlan(plan),
                              child: Text(
                                appStrings.pick(
                                  'REQUEST CHANGE',
                                  'SOLICITAR CAMBIO',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                if (pending == null &&
                    _saasPlans.any(
                      (p) =>
                          saasPlanCapacityShortfall(
                            active: active,
                            limit: (p['active_member_limit'] as num?)?.toInt(),
                          ) >
                          0,
                    ))
                  TextButton(
                    key: const ValueKey('saas-manage-members'),
                    onPressed: () {
                      Navigator.pop(c);
                      context.go('/app?section=panel');
                    },
                    child: Text(
                      appStrings.pick('MANAGE MEMBERS', 'GESTIONAR MIEMBROS'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(appStrings.pick('Close', 'Cerrar')),
          ),
        ],
      );
    },
  );

  void _applyGym(Map<String, dynamic>? gym) {
    if (gym == null) return;
    _gymId = gym['id']?.toString() ?? _gymId;
    _business.text = (gym['business_name'] ?? gym['name'] ?? '').toString();
    _phone.text = (gym['phone'] ?? '').toString();
    _email.text = (gym['email'] ?? '').toString();
    _website.text = (gym['website'] ?? '').toString();
    _address.text = (gym['address'] ?? '').toString();
    _logoUrl = gym['logo_url']?.toString();
    _gymCode = gym['gym_code']?.toString();
    _stripeAccountId = gym['stripe_account_id']?.toString();
    _stripeOnboardingComplete = gym['stripe_onboarding_complete'] == true;
    _stripeChargesEnabled = gym['stripe_charges_enabled'] == true;
    _stripePayoutsEnabled = gym['stripe_payouts_enabled'] == true;
    if (gym['saas_usage'] is Map) {
      _saasUsage = Map<String, dynamic>.from(gym['saas_usage'] as Map);
    }
    if (gym['saas_plans'] is List) {
      _saasPlans = List<Map<String, dynamic>>.from(gym['saas_plans'] as List);
    }
    if (gym['saas_pending_request'] is Map) {
      _pendingSaasRequest = Map<String, dynamic>.from(
        gym['saas_pending_request'] as Map,
      );
    }
  }

  Future<void> _uploadLogo() async {
    final gymId = _gymId;
    if (gymId == null || _uploadingLogo) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 900,
    );

    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      uiSettings: [
        IOSUiSettings(
          title: appStrings.updateLogo,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        AndroidUiSettings(
          toolbarTitle: appStrings.updateLogo,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
      ],
    );

    if (cropped == null) return;

    setState(() => _uploadingLogo = true);

    try {
      final bytes = await cropped.readAsBytes();
      final path = '$gymId.jpg';

      await Supabase.instance.client.storage
          .from('gym-logos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('gym-logos')
          .getPublicUrl(path);

      final freshUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client
          .from('gyms')
          .update({'logo_url': freshUrl})
          .eq('id', gymId);

      await _loadGym();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.logoUpdated)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.updateLogoError(e))));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _refreshStripeStatus() async {
    final injected = widget.statusRefresherForTesting;
    if (injected != null) {
      await injected();
      return;
    }
    if (_gymId == null) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'refresh-stripe-connect-account',
      );
      await _loadGym();
    } catch (_) {
      // Keep settings screen stable if Stripe status cannot be refreshed.
    }
  }

  Future<void> _connectStripe() async {
    if (_connectingStripe) return;

    final injected = widget.onboardingOpenerForTesting;
    if (injected != null) {
      await injected();
      return;
    }

    setState(() => _connectingStripe = true);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'create-stripe-connect-account',
      );

      final data = response.data;
      final url = data is Map ? data['url']?.toString() : null;

      if (url == null || url.isEmpty) {
        throw Exception('Missing Stripe onboarding URL');
      }

      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw Exception('Could not open Stripe onboarding');
      }

      await _refreshStripeStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.connectStripeError(e))));
    } finally {
      if (mounted) setState(() => _connectingStripe = false);
    }
  }

  Future<void> _saveGym() async {
    final gymId = _gymId;
    if (gymId == null || _saving) return;

    setState(() => _saving = true);

    try {
      await Supabase.instance.client
          .from('gyms')
          .update({
            'business_name': _business.text.trim(),
            'phone': _phone.text.trim(),
            'email': _email.text.trim(),
            'website': _website.text.trim(),
            'address': _address.text.trim(),
          })
          .eq('id', gymId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.gymInformationUpdated)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.updateGymError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _business.dispose();
    _phone.dispose();
    _email.dispose();
    _website.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: Column(
        children: [
          AppDetailHeader(
            title: appStrings.gymInformation,
            onBack: () => Navigator.of(context).maybePop(),
            leadingColor: AppColors.primary,
          ),
          Expanded(
            child: _loading
                ? const AppCenteredLoadingIndicator(color: AppColors.primary)
                : ListView(
                    key: const ValueKey('gym-information-scroll'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.screenX,
                      AppSpacing.md,
                      AppSpacing.screenX,
                      AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    children: [
                      Center(
                        child: _GymLogoPicker(
                          logoUrl: _logoUrl,
                          uploading: _uploadingLogo,
                          onTap: _uploadLogo,
                        ),
                      ),
                      if (_gymCode != null && _gymCode!.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _GymQrCard(gymCode: _gymCode!),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      AppFormSectionLabel(
                        label: appStrings.pick('PLAN', 'PLAN'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_saasUsage != null)
                        ListTile(
                          key: const ValueKey('gym-saas-plan-card'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.workspace_premium_outlined,
                            color: AppColors.primary,
                          ),
                          title: Text(
                            _saasUsage!['plan_name']?.toString() ?? 'FREE',
                          ),
                          subtitle: Text(
                            _saasUsage!['active_member_limit'] == null
                                ? '${_saasUsage!['active_athlete_count']} ${appStrings.pick('active athletes · Unlimited', 'atletas activos · Ilimitado')}'
                                : '${_saasUsage!['active_athlete_count']} / ${_saasUsage!['active_member_limit']} ${appStrings.pick('active athletes', 'atletas activos')}',
                          ),
                          trailing: TextButton(
                            onPressed: _showSaasPlans,
                            child: Text(
                              appStrings.pick('View plan', 'Ver plan'),
                            ),
                          ),
                        ),
                      if (_saasUsage?['over_limit'] == true)
                        Text(
                          appStrings.pick(
                            'This gym is over its active athlete limit. Existing athletes keep access, but new activations are blocked.',
                            'Este gimnasio supera su límite de atletas activos. Los atletas existentes conservan el acceso, pero se bloquean nuevas activaciones.',
                          ),
                        )
                      else if (_saasUsage?['limit_reached'] == true)
                        Text(appStrings.gymMemberLimitReached),
                      const SizedBox(height: AppSpacing.lg),
                      AppFormSectionLabel(
                        label: appStrings.gymInformation.toUpperCase(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _GymInfoField(
                        key: const ValueKey('gym-business-field'),
                        label: appStrings.profileGymName,
                        icon: Icons.storefront_outlined,
                        controller: _business,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _GymInfoField(
                        label: appStrings.phone,
                        icon: Icons.phone_outlined,
                        controller: _phone,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _GymInfoField(
                        label: appStrings.authEmail,
                        icon: Icons.email_outlined,
                        controller: _email,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _GymInfoField(
                        label: appStrings.website,
                        icon: Icons.language_outlined,
                        controller: _website,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _GymInfoField(
                        label: appStrings.address,
                        icon: Icons.location_on_outlined,
                        controller: _address,
                        maxLines: 2,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppFormSubmitButton(
                        key: const ValueKey('gym-information-save'),
                        label: appStrings.saveChanges,
                        loading: _saving,
                        enabled: !_saving,
                        onPressed: _saveGym,
                        accentColor: AppColors.primary,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppFormSectionLabel(
                        label: appStrings.documents.toUpperCase(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ListTile(
                        key: const ValueKey('gym-documents-entry'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.description_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          appStrings.manageDocuments,
                          style: AppTypography.body(context),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/gym-documents'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppFormSectionLabel(
                        label: appStrings.gymPayments.toUpperCase(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _GymStripeStatus(
                        state: gymStripeConnectState(
                          accountId: _stripeAccountId,
                          onboardingComplete: _stripeOnboardingComplete,
                          chargesEnabled: _stripeChargesEnabled,
                          payoutsEnabled: _stripePayoutsEnabled,
                        ),
                      ),
                      if (stripeConnectSetupEnabled) ...[
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton(
                          onPressed: _connectingStripe
                              ? null
                              : gymStripeConnectState(
                                      accountId: _stripeAccountId,
                                      onboardingComplete:
                                          _stripeOnboardingComplete,
                                      chargesEnabled: _stripeChargesEnabled,
                                      payoutsEnabled: _stripePayoutsEnabled,
                                    ) ==
                                    GymStripeConnectState.paymentsEnabled
                              ? _refreshStripeStatus
                              : _connectStripe,
                          child: Text(
                            _stripeAccountId == null
                                ? appStrings.connectStripe
                                : _stripeChargesEnabled
                                ? appStrings.stripeConnected
                                : appStrings.pick(
                                    'CONTINUE SETUP',
                                    'CONTINUAR CONFIGURACIÓN',
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
    ),
  );
}

class _GymStripeStatus extends StatelessWidget {
  const _GymStripeStatus({required this.state});

  final GymStripeConnectState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      GymStripeConnectState.disconnected => appStrings.stripeNotConnected,
      GymStripeConnectState.setupPending => appStrings.stripeSetupPending,
      GymStripeConnectState.chargesDisabled => appStrings.stripeChargesDisabled,
      GymStripeConnectState.paymentsEnabled => appStrings.stripePaymentsEnabled,
    };
    final enabled = state == GymStripeConnectState.paymentsEnabled;

    return Container(
      key: const ValueKey('gym-stripe-status'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle_outline : Icons.info_outline_rounded,
            color: enabled
                ? AppColors.primary
                : AppColors.textSecondary(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.body(context))),
        ],
      ),
    );
  }
}

class _GymInfoField extends StatelessWidget {
  const _GymInfoField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.maxLines = 1,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      cursorColor: AppColors.primary,
      style: appFormValueStyle(context),
      decoration: appFormInput(
        context,
        icon: icon,
        accentColor: AppColors.primary,
        hintText: label,
      ),
    );
  }
}

class _GymQrCard extends StatelessWidget {
  const _GymQrCard({required this.gymCode});

  final String gymCode;

  @override
  Widget build(BuildContext context) {
    final payload = 'athlete615://join-gym?gym_code=$gymCode';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        children: [
          Text(
            appStrings.gymQrCode.toUpperCase(),
            style: AppTypography.sectionTitle(context),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            gymCode,
            style: AppTypography.itemTitle(
              context,
            ).copyWith(color: AppColors.primary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            appStrings.gymQrCodeMessage,
            textAlign: TextAlign.center,
            style: AppTypography.helper(context),
          ),
        ],
      ),
    );
  }
}

class _GymLogoPicker extends StatelessWidget {
  const _GymLogoPicker({
    required this.logoUrl,
    required this.uploading,
    required this.onTap,
  });

  final String? logoUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl != null && logoUrl!.trim().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: uploading ? null : onTap,
      child: Column(
        children: [
          Container(
            width: 118,
            height: 118,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: uploading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : hasLogo
                ? Image.network(logoUrl!, fit: BoxFit.cover)
                : Icon(
                    Icons.image_outlined,
                    size: 36,
                    color: AppColors.textSecondary(context),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            appStrings.updateLogo,
            style: AppTypography.buttonLabel(
              context,
            ).copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
