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
import '../../../../core/widgets/app_secondary_action_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _stripePaymentsEnabled = false;

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
    if (_stripePaymentsEnabled && state == AppLifecycleState.resumed) {
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
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

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
    body: SafeArea(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AppSecondaryActionHeader(
                onBack: () => Navigator.of(context).maybePop(),
              ),
              IgnorePointer(
                child: Text(
                  appStrings.gymInformation.toUpperCase(),
                  key: const ValueKey('gym-information-title'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
                      if (_stripePaymentsEnabled) ...[
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton(
                          onPressed: _stripeChargesEnabled
                              ? _refreshStripeStatus
                              : _connectStripe,
                          child: Text(
                            _stripeChargesEnabled
                                ? appStrings.stripeConnected
                                : appStrings.connectStripe,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
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
