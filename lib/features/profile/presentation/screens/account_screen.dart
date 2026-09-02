import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_keyboard_dismissible.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../../../../core/widgets/app_detail_header.dart';
import '../../../auth/data/auth_repository.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.profileLoaderForTesting});

  final Future<Map<String, dynamic>?> Function()? profileLoaderForTesting;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _fullName = TextEditingController();
  final _birthDate = TextEditingController();
  bool _loading = false;
  bool _uploadingAvatar = false;
  Map<String, dynamic>? _profile;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _birthDate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile =
        await (widget.profileLoaderForTesting?.call() ?? _repo.myProfile());
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _fullName.text = profile?['full_name']?.toString() ?? '';
      _birthDate.text = profile?['birth_date']?.toString() ?? '';
    });
  }

  String _dateLabel(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return appStrings.notSet;
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate:
          DateTime.tryParse(_birthDate.text) ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _birthDate.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _save() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _loading) return;
    setState(() => _loading = true);
    try {
      final name = _fullName.text.trim();
      final birthDate = _birthDate.text.trim();
      await Supabase.instance.client
          .from('profiles')
          .update({
            'full_name': name.isEmpty ? null : name,
            'birth_date': birthDate.isEmpty ? null : birthDate,
          })
          .eq('id', userId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.profileUpdated)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.updateProfileError(error))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: appStrings.profileDeleteAccount,
      message: appStrings.profileDeleteConfirm,
      confirmLabel: appStrings.profileDeleteAccount,
      cancelLabel: appStrings.cancel,
    );
    if (!confirmed) return;
    setState(() => _loading = true);
    try {
      await _repo.deleteMyAccount();
      if (mounted) context.go('/login');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.deleteAccountError(error))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadAvatar() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _uploadingAvatar) return;
    final picked = await ImagePicker().pickImage(
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
          title: appStrings.updatePhoto,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        AndroidUiSettings(
          toolbarTitle: appStrings.updatePhoto,
          lockAspectRatio: true,
        ),
      ],
    );
    if (cropped == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final path = '$userId.jpg';
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            await cropped.readAsBytes(),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);
      await Supabase.instance.client
          .from('profiles')
          .update({
            'avatar_url':
                '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}',
          })
          .eq('id', userId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.photoUpdated)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.updatePhotoError(error))),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: AppKeyboardDismissible(
      child: Column(
          children: [
            AppDetailHeader(
              title: appStrings.profileAccount,
              onBack: () => Navigator.of(context).maybePop(),
              leadingColor: AppColors.primary,
            ),
            Expanded(
              child: _profile == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : AccountFormContent(
                      fullName: _fullName,
                      birthDateLabel: _dateLabel(_birthDate.text),
                      email:
                          _profile?['email']?.toString() ??
                          Supabase.instance.client.auth.currentUser?.email ??
                          '-',
                      avatarUrl: _profile?['avatar_url']?.toString(),
                      uploadingAvatar: _uploadingAvatar,
                      loading: _loading,
                      onAvatarTap: _uploadAvatar,
                      onBirthDateTap: _pickBirthDate,
                      onSave: _save,
                      onDelete: _deleteAccount,
                    ),
            ),
          ],
      ),
    ),
  );
}

class AccountFormContent extends StatelessWidget {
  const AccountFormContent({
    super.key,
    required this.fullName,
    required this.birthDateLabel,
    required this.email,
    required this.avatarUrl,
    required this.uploadingAvatar,
    required this.loading,
    required this.onAvatarTap,
    required this.onBirthDateTap,
    required this.onSave,
    required this.onDelete,
  });

  final TextEditingController fullName;
  final String birthDateLabel;
  final String email;
  final String? avatarUrl;
  final bool uploadingAvatar;
  final bool loading;
  final VoidCallback onAvatarTap;
  final VoidCallback onBirthDateTap;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('account-scroll'),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenX,
      AppSpacing.md,
      AppSpacing.screenX,
      48,
    ),
    children: [
      Center(
        child: Column(
          children: [
            _AccountAvatar(
              displayName: fullName.text,
              avatarUrl: avatarUrl,
              uploading: uploadingAvatar,
              onTap: onAvatarTap,
            ),
            TextButton(
              key: const ValueKey('account-change-photo'),
              onPressed: uploadingAvatar ? null : onAvatarTap,
              child: Text(
                appStrings.updatePhoto,
                style: GoogleFonts.barlow(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AppFormSectionLabel(
        label: appStrings.pick('PERSONAL DETAILS', 'DATOS PERSONALES'),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        key: const ValueKey('account-full-name'),
        controller: fullName,
        textCapitalization: TextCapitalization.words,
        style: appFormValueStyle(context),
        decoration: appFormInput(
          context,
          icon: Icons.person_outline_rounded,
          accentColor: AppColors.primary,
          hintText: appStrings.fullName,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppFormActionField(
        icon: Icons.calendar_month_outlined,
        value: birthDateLabel,
        placeholder: birthDateLabel == appStrings.notSet,
        onTap: onBirthDateTap,
        accentColor: AppColors.primary,
      ),
      const SizedBox(height: AppSpacing.lg),
      AppFormSectionLabel(label: appStrings.pick('ACCOUNT', 'CUENTA')),
      const SizedBox(height: AppSpacing.sm),
      Container(
        key: const ValueKey('account-email'),
        constraints: const BoxConstraints(minHeight: AppSizes.fieldHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt(context),
          borderRadius: BorderRadius.circular(AppRadii.input),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.email_outlined,
              color: AppColors.textSecondary(context),
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: appFormValueStyle(
                  context,
                ).copyWith(color: AppColors.textSecondary(context)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      AppFormSubmitButton(
        key: const ValueKey('account-save'),
        label: appStrings.saveChanges,
        loading: loading,
        enabled: true,
        onPressed: onSave,
        accentColor: AppColors.primary,
      ),
      const SizedBox(height: AppSpacing.lg),
      TextButton(
        key: const ValueKey('account-delete'),
        onPressed: loading ? null : onDelete,
        child: Text(
          appStrings.profileDeleteAccount,
          style: GoogleFonts.barlow(
            color: AppColors.danger,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.displayName,
    required this.avatarUrl,
    required this.uploading,
    required this.onTap,
  });

  final String displayName;
  final String? avatarUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final valid = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return InkWell(
      key: const ValueKey('account-avatar'),
      customBorder: const CircleBorder(),
      onTap: uploading ? null : onTap,
      child: CircleAvatar(
        radius: 48,
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        foregroundImage: valid ? NetworkImage(avatarUrl!) : null,
        child: uploading
            ? const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              )
            : valid
            ? null
            : Text(
                displayName.isEmpty ? 'A' : displayName[0].toUpperCase(),
                style: GoogleFonts.barlow(
                  color: AppColors.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
