import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../auth/data/auth_repository.dart';

Color _profileHubBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF252525) : const Color(0xFFF1F2F4);
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.gymName,
    required this.onGymNameChanged,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final String? gymName;
  final Future<void> Function() onGymNameChanged;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _fullName = TextEditingController();
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
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _repo.myProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _fullName.text = profile?['full_name']?.toString() ?? '';
    });
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

  Future<void> _logout() async {
    await _repo.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.couldNotOpenLink)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '-';
    final profileName = _profile?['full_name']?.toString().trim() ?? '';
    final displayName = profileName.isNotEmpty
        ? profileName
        : 'ATHLETE615 Member';
    final avatarUrl = _profile?['avatar_url']?.toString();

    return Scaffold(
      backgroundColor: _profileHubBackground(context),
      body: Column(
        children: [
          _ProfileHeader(
            gymName: widget.gymName,
            unreadNotifications: widget.unreadNotifications,
            onOpenNotifications: widget.onOpenNotifications,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_profile == null)
                  const _ProfileSkeleton()
                else
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
                        child: Center(
                          child: Column(
                            children: [
                              _ProfileAvatar(
                                displayName: displayName,
                                avatarUrl: avatarUrl,
                                uploading: _uploadingAvatar,
                                onTap: _uploadAvatar,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                displayName.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: _ProfileText.title.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 24,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                email,
                                textAlign: TextAlign.center,
                                style: _ProfileText.body.copyWith(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _ProfileMenuSection(
                        children: [
                          _ProfileListCard(
                            children: [
                              _ProfileMenuRow(
                                title: appStrings.profileAccount,
                                onTap: () => context.push('/account'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 34),
                          _ProfileListCard(
                            children: [
                              _ProfileMenuRow(
                                title: appStrings.profileTraining,
                                onTap: () => context.push('/training'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _ProfileListCard(
                            children: [
                              _ProfileMenuRow(
                                title: appStrings.profileMembership,
                                onTap: () => context.push('/membership'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _ProfileListCard(
                            children: [
                              _ProfileMenuRow(
                                title: appStrings.personalRecords,
                                onTap: () => context.push('/records'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 34),
                          _ProfileListCard(
                            children: [
                              _ProfileMenuRow(
                                title: appStrings.profileHelp,
                                onTap: () =>
                                    _openUrl('https://athlete615.com/support'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _ProfileListCard(
                            children: [
                              _ProfileMenuRow(
                                title: appStrings.profilePrivacyPolicy,
                                onTap: () => _openUrl(
                                  'https://athlete615.com/privacy-policy',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _ProfileListCard(
                            children: [
                              _ProfileMenuRow(
                                title: appStrings.profileTerms,
                                onTap: () => _openUrl(
                                  'https://athlete615.com/terms-and-conditions',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 34),
                          _ProfileListCard(
                            children: [
                              _ProfileMenuRow(
                                title: appStrings.profileLogout,
                                isDanger: true,
                                onTap: _logout,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileText {
  const _ProfileText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.3,
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.gymName,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final String? gymName;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  TextStyle _font(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = const Color(0xFF111318),
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.barlowCondensed(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt(context),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 132,
                    child: Text(
                      gymName ?? appStrings.appBrand,
                      style: _font(
                        16,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                        letterSpacing: -0.3,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.profileHeaderTitle,
                      style: _font(
                        22,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: 132,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onOpenNotifications,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(
                              Icons.notifications,
                              size: 32,
                              color: AppColors.accent,
                            ),
                          ),
                          if (unreadNotifications > 0)
                            Positioned(
                              right: -7,
                              top: -7,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.danger,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  unreadNotifications > 99
                                      ? '99+'
                                      : unreadNotifications.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
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
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
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
      borderRadius: BorderRadius.circular(AppRadii.panel),
      onTap: uploading ? null : onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.panel),
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
                        fontSize: 22,
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

class _ProfileMenuSection extends StatelessWidget {
  const _ProfileMenuSection({required this.children});

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

class _ProfileListCard extends StatelessWidget {
  const _ProfileListCard({required this.children});

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

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({
    required this.title,
    required this.onTap,
    this.isDanger = false,
  });

  final String title;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppColors.danger : AppColors.textPrimary(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0,
                  height: 1.2,
                ),
              ),
            ),
            if (!isDanger)
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

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        children: const [
          _SkeletonCard(lines: 2, avatar: true),
          SizedBox(height: 18),
          _SkeletonCard(lines: 4),
          SizedBox(height: 18),
          _SkeletonCard(lines: 3),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.lines, this.avatar = false});

  final int lines;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.border(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (avatar) ...[
            Row(
              children: [
                const _SkeletonBox(width: 54, height: 54, radius: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SkeletonBox(
                        width: double.infinity,
                        height: 18,
                        radius: 999,
                      ),
                      SizedBox(height: 10),
                      _SkeletonBox(width: 150, height: 14, radius: 999),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            for (var i = 0; i < lines; i++) ...[
              _SkeletonBox(
                width: i == 0 ? 130 : double.infinity,
                height: i == 0 ? 14 : 18,
                radius: 999,
              ),
              if (i != lines - 1) const SizedBox(height: 14),
            ],
          ],
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
