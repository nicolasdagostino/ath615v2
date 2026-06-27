import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Color _gymSettingsBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF252525) : const Color(0xFFF1F2F4);
}

class GymSettingsScreen extends StatefulWidget {
  const GymSettingsScreen({super.key});

  @override
  State<GymSettingsScreen> createState() => _GymSettingsScreenState();
}

class _GymSettingsScreenState extends State<GymSettingsScreen> {
  final _business = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();

  String? _gymId;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    _loadGym();
  }

  Future<void> _loadGym() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('gym_id')
        .eq('id', user.id)
        .single();

    _gymId = profile['gym_id']?.toString();

    if (_gymId != null) {
      final gym = await Supabase.instance.client
          .from('gyms')
          .select('business_name,phone,email,website,address,name,logo_url')
          .eq('id', _gymId!)
          .single();

      _business.text = (gym['business_name'] ?? gym['name'] ?? '').toString();
      _phone.text = (gym['phone'] ?? '').toString();
      _email.text = (gym['email'] ?? '').toString();
      _website.text = (gym['website'] ?? '').toString();
      _address.text = (gym['address'] ?? '').toString();
      _logoUrl = gym['logo_url']?.toString();
    }

    if (!mounted) return;
    setState(() => _loading = false);
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
    _business.dispose();
    _phone.dispose();
    _email.dispose();
    _website.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _gymSettingsBackground(context),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  appStrings.gymInformation,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(context),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appStrings.gymInformation.toUpperCase(),
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  else ...[
                    Center(
                      child: _GymLogoPicker(
                        logoUrl: _logoUrl,
                        uploading: _uploadingLogo,
                        onTap: _uploadLogo,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _GymInfoField(
                      label: appStrings.profileGymName,
                      controller: _business,
                    ),
                    const SizedBox(height: 12),
                    _GymInfoField(label: appStrings.phone, controller: _phone),
                    const SizedBox(height: 12),
                    _GymInfoField(
                      label: appStrings.authEmail,
                      controller: _email,
                    ),
                    const SizedBox(height: 12),
                    _GymInfoField(
                      label: appStrings.website,
                      controller: _website,
                    ),
                    const SizedBox(height: 12),
                    _GymInfoField(
                      label: appStrings.address,
                      controller: _address,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 18),
                    AppButton(
                      label: appStrings.saveChanges,
                      loading: _saving,
                      onPressed: _saveGym,
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
}

class _GymInfoField extends StatelessWidget {
  const _GymInfoField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      cursorColor: AppColors.accent,
      style: GoogleFonts.barlowCondensed(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary(context),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.barlowCondensed(
          color: AppColors.textSecondary(context),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.surfaceAlt(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
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
                    child: CircularProgressIndicator(color: AppColors.accent),
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
            style: GoogleFonts.barlowCondensed(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
