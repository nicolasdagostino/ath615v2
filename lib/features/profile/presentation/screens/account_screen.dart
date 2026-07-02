import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../auth/data/auth_repository.dart';

Color _profileHubBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF252525) : const Color(0xFFF1F2F4);
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _fullName = TextEditingController();
  final _birthDate = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

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
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _repo.myProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _fullName.text = profile?['full_name']?.toString() ?? '';
      _birthDate.text = profile?['birth_date']?.toString() ?? '';
    });
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return appStrings.notSet;
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.day}/${date.month}/${date.year}';
  }

  String _dateInputValue(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _pickBirthDate() async {
    final current = DateTime.tryParse(_birthDate.text);
    final now = DateTime.now();

    final picked = await showAppDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked == null) return;

    setState(() {
      _birthDate.text = _dateInputValue(picked);
    });
  }

  Future<void> _openEditAccountSheet({required bool editBirthDate}) async {
    final title = editBirthDate ? appStrings.birthDate : appStrings.fullName;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border(context), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: _AccountText.header.copyWith(
                      color: AppColors.textPrimary(context),
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: editBirthDate ? _birthDate : _fullName,
                    readOnly: editBirthDate,
                    textCapitalization: TextCapitalization.words,
                    cursorColor: AppColors.accent,
                    style: _AccountText.body.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _inputDecoration(context, title).copyWith(
                      suffixIcon: editBirthDate
                          ? const Icon(
                              Icons.calendar_month_rounded,
                              color: AppColors.accent,
                            )
                          : null,
                    ),
                    onTap: editBirthDate ? _pickBirthDate : null,
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: appStrings.saveChanges,
                    loading: _loading,
                    onPressed: () async {
                      final navigator = Navigator.of(sheetContext);
                      await _saveAccountInfo();
                      if (mounted) navigator.pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveAccountInfo() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final fullName = _fullName.text.trim();
    final birthDate = _birthDate.text.trim();

    setState(() => _loading = true);

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'full_name': fullName.isEmpty ? null : fullName,
            'birth_date': birthDate.isEmpty ? null : birthDate,
          })
          .eq('id', userId);

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.profileUpdated)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.updateProfileError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(AppSpacing.sheetMargin),
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border(context), width: 1),
                boxShadow: AppShadows.card(context),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: _AccountText.header.copyWith(
                      color: AppColors.textPrimary(context),
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: _AccountText.body.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _AccountConfirmButton(
                          label: appStrings.cancel,
                          onTap: () => Navigator.of(sheetContext).pop(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AccountConfirmButton(
                          label: confirmLabel,
                          danger: danger,
                          onTap: () => Navigator.of(sheetContext).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  Future<void> _openChangePasswordSheet() async {
    _password.clear();
    _confirmPassword.clear();

    var obscurePassword = true;
    var obscureConfirmPassword = true;
    var loading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final password = _password.text.trim();
            final confirmPassword = _confirmPassword.text.trim();
            final canSubmit =
                password.length >= 6 && password == confirmPassword;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(AppSpacing.sheetMargin),
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.border(context),
                      width: 1,
                    ),
                    boxShadow: AppShadows.card(context),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Text(
                        appStrings.profileChangePassword.toUpperCase(),
                        style: _AccountText.header.copyWith(
                          color: AppColors.textPrimary(context),
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        onChanged: (_) => setSheetState(() {}),
                        obscureText: obscurePassword,
                        cursorColor: AppColors.accent,
                        style: _AccountText.body.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                        decoration:
                            _inputDecoration(
                              context,
                              appStrings.profileNewPassword,
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                color: AppColors.accent,
                                onPressed: () {
                                  setSheetState(() {
                                    obscurePassword = !obscurePassword;
                                  });
                                },
                              ),
                            ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmPassword,
                        onChanged: (_) => setSheetState(() {}),
                        obscureText: obscureConfirmPassword,
                        cursorColor: AppColors.accent,
                        style: _AccountText.body.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                        decoration:
                            _inputDecoration(
                              context,
                              appStrings.profileConfirmPassword,
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                color: AppColors.accent,
                                onPressed: () {
                                  setSheetState(() {
                                    obscureConfirmPassword =
                                        !obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                      ),
                      const SizedBox(height: 16),
                      AppButton(
                        label: appStrings.profileChangePassword,
                        loading: loading,
                        onPressed: loading || !canSubmit
                            ? null
                            : () async {
                                final navigator = Navigator.of(sheetContext);

                                setSheetState(() => loading = true);

                                var updated = false;
                                try {
                                  updated = await _changePassword();
                                } finally {
                                  if (context.mounted) {
                                    setSheetState(() => loading = false);
                                  }
                                }

                                if (mounted && updated) navigator.pop();
                              },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _changePassword() async {
    if (_password.text != _confirmPassword.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.profilePasswordsDoNotMatch)),
      );
      return false;
    }

    setState(() => _loading = true);

    try {
      await _repo.updatePassword(_password.text);
      _password.clear();
      _confirmPassword.clear();

      if (!mounted) return false;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.passwordUpdated)));

      return true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirmAction(
      title: appStrings.profileDeleteAccount,
      message: appStrings.profileDeleteConfirm,
      confirmLabel: appStrings.profileDeleteAccount,
      danger: true,
    );

    if (!confirmed) return;

    setState(() => _loading = true);

    try {
      await _repo.deleteMyAccount();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.deleteAccountError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadAvatar() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _uploadingAvatar) return;

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
          title: appStrings.updatePhoto,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        AndroidUiSettings(
          toolbarTitle: appStrings.updatePhoto,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
      ],
    );

    if (cropped == null) return;

    setState(() => _uploadingAvatar = true);

    try {
      final bytes = await cropped.readAsBytes();
      final path = '$userId.jpg';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);

      final freshUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': freshUrl})
          .eq('id', userId);

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.photoUpdated)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.updatePhotoError(e))));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '-';
    final fullName = _profile?['full_name']?.toString().trim() ?? '';
    final displayName = fullName.isNotEmpty ? fullName : 'ATHLETE615 Member';
    final avatarUrl = _profile?['avatar_url']?.toString();

    return Scaffold(
      backgroundColor: _profileHubBackground(context),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Row(
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
                    appStrings.profileAccount,
                    style: _AccountText.header.copyWith(
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_profile == null)
              const _AccountSkeleton()
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: Column(
                    children: [
                      _AccountAvatar(
                        displayName: displayName,
                        avatarUrl: avatarUrl,
                        uploading: _uploadingAvatar,
                        onTap: _uploadAvatar,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        appStrings.updatePhoto.toUpperCase(),
                        style: _AccountText.body.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: _AccountText.body.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),
              _AccountMenuSection(
                children: [
                  _AccountListCard(
                    children: [
                      _AccountInfoRow(
                        label: appStrings.fullName,
                        value: fullName.isEmpty ? appStrings.notSet : fullName,
                        onTap: () =>
                            _openEditAccountSheet(editBirthDate: false),
                      ),
                      const _AccountInsetDivider(),
                      _AccountInfoRow(
                        label: appStrings.birthDate,
                        value: _formatDate(_profile?['birth_date']?.toString()),
                        onTap: () => _openEditAccountSheet(editBirthDate: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AccountListCard(
                    children: [
                      _AccountMenuRow(
                        title: appStrings.profileChangePassword,
                        onTap: _openChangePasswordSheet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AccountListCard(
                    children: [
                      _AccountMenuRow(
                        title: appStrings.profileSettings,
                        onTap: () => context.push('/settings'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 34),
                  _AccountListCard(
                    children: [
                      _AccountMenuRow(
                        title: appStrings.profileDeleteAccount,
                        danger: true,
                        onTap: _deleteAccount,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountText {
  const _AccountText._();

  static TextStyle header = GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    fontSize: 15.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.2,
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
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: uploading ? null : onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 82,
              height: 82,
              alignment: Alignment.center,
              color: AppColors.surfaceAlt(context),
              child: hasAvatar
                  ? Image.network(
                      avatarUrl!,
                      width: 82,
                      height: 82,
                      fit: BoxFit.cover,
                    )
                  : Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'A',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                        height: 1.0,
                      ),
                    ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.background(context),
                  width: 2,
                ),
              ),
              child: uploading
                  ? const Padding(
                      padding: EdgeInsets.all(5),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      Icons.camera_alt_rounded,
                      color: AppColors.textPrimary(context),
                      size: 14,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountMenuSection extends StatelessWidget {
  const _AccountMenuSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      color: _profileHubBackground(context),
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 72),
      child: Column(children: children),
    );
  }
}

class _AccountListCard extends StatelessWidget {
  const _AccountListCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context), width: 1),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(children: children),
    );
  }
}

class _AccountInfoRow extends StatelessWidget {
  const _AccountInfoRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: _AccountText.body.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: _AccountText.body.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountInsetDivider extends StatelessWidget {
  const _AccountInsetDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        width: double.infinity,
        height: 1,
        color: isDark ? const Color(0xFF4A4A4A) : const Color(0xFFE1E4E8),
      ),
    );
  }
}

class _AccountMenuRow extends StatelessWidget {
  const _AccountMenuRow({
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: _AccountText.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!danger)
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textSecondary(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountConfirmButton extends StatelessWidget {
  const _AccountConfirmButton({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.input),
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt(context),
          borderRadius: BorderRadius.circular(AppRadii.input),
          border: Border.all(color: AppColors.border(context), width: 1),
        ),
        child: Text(
          label.toUpperCase(),
          style: _AccountText.body.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlowCondensed(
      color: AppColors.textSecondary(context),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    labelText: null,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    filled: true,
    fillColor: AppColors.surfaceAlt(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
  );
}

class _AccountSkeleton extends StatelessWidget {
  const _AccountSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 220);
  }
}
