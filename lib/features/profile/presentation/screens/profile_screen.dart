import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../../../auth/data/auth_repository.dart';

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
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _gymName = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _birthDate = TextEditingController();
  bool _loading = false;
  bool _uploadingAvatar = false;
  String _appVersion = '';
  Map<String, dynamic>? _profile;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _load();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();

    if (!mounted) return;

    setState(() {
      _appVersion = 'v${info.version}+${info.buildNumber}';
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    _gymName.dispose();
    _fullName.dispose();
    _phone.dispose();
    _birthDate.dispose();
    super.dispose();
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
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

  Future<void> _load() async {
    final profile = await _repo.myProfile();
    final gymId = profile?['gym_id'] as String?;

    String gymName = '';
    if (gymId != null) {
      final gym = await Supabase.instance.client
          .from('gyms')
          .select('name')
          .eq('id', gymId)
          .maybeSingle();

      gymName = gym?['name']?.toString() ?? '';
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _gymName.text = gymName;
      _fullName.text = profile?['full_name']?.toString() ?? '';
      _phone.text = profile?['phone']?.toString() ?? '';
      _birthDate.text = profile?['birth_date']?.toString() ?? '';
    });
  }

  String _displayRole(String? role) {
    switch (role) {
      case 'athlete':
        return 'MEMBER';
      case 'admin':
        return 'COACH';
      case 'owner':
        return 'OWNER';
      default:
        return role?.toUpperCase() ?? '-';
    }
  }

  Future<void> _openPersonalInfoSheet() async {
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
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.editPersonalInformation.toUpperCase(),
                    style: _ProfileText.sectionTitle,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _fullName,
                    textCapitalization: TextCapitalization.words,
                    style: _ProfileText.input,
                    decoration: _inputDecoration(appStrings.fullName),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    style: _ProfileText.input,
                    decoration: _inputDecoration(appStrings.phone),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _birthDate,
                    readOnly: true,
                    style: _ProfileText.input,
                    decoration: _inputDecoration(appStrings.birthDate).copyWith(
                      suffixIcon: const Icon(Icons.calendar_month_rounded),
                    ),
                    onTap: _pickBirthDate,
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: appStrings.saveChanges,
                    loading: _loading,
                    onPressed: () async {
                      final navigator = Navigator.of(sheetContext);
                      await _savePersonalInfo();
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

  Future<void> _savePersonalInfo() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final fullName = _fullName.text.trim();
    final phone = _phone.text.trim();
    final birthDate = _birthDate.text.trim();

    setState(() => _loading = true);

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'full_name': fullName.isEmpty ? null : fullName,
            'phone': phone.isEmpty ? null : phone,
            'birth_date': birthDate.isEmpty ? null : birthDate,
          })
          .eq('id', userId);

      await _load();

      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.updateProfileError(e))));
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
    final profileName = _profile?['full_name']?.toString().trim() ?? '';
    final displayName = profileName.isNotEmpty
        ? profileName
        : 'ATHLETE615 Member';
    final avatarUrl = _profile?['avatar_url']?.toString();

    return Scaffold(
      backgroundColor: const Color(0xFF252525),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileCard(
                          child: Row(
                            children: [
                              _ProfileAvatar(
                                displayName: displayName,
                                avatarUrl: avatarUrl,
                                uploading: _uploadingAvatar,
                                onTap: _uploadAvatar,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: _ProfileText.title,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _displayRole(
                                        _profile?['role']?.toString(),
                                      ),
                                      style: _ProfileText.subtle,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _ProfileCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appStrings.personalInformation.toUpperCase(),
                                style: _ProfileText.sectionTitle,
                              ),
                              const SizedBox(height: 14),
                              _InfoRow(
                                label: appStrings.fullName,
                                value: profileName.isEmpty
                                    ? appStrings.notSet
                                    : profileName,
                              ),
                              _InfoRow(
                                label: appStrings.authEmail,
                                value: email,
                              ),
                              _InfoRow(
                                label: appStrings.phone,
                                value:
                                    (_profile?['phone']
                                            ?.toString()
                                            .trim()
                                            .isEmpty ??
                                        true)
                                    ? appStrings.notSet
                                    : _profile!['phone'].toString(),
                              ),
                              _InfoRow(
                                label: appStrings.birthDate,
                                value: _formatDate(
                                  _profile?['birth_date']?.toString(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppButton(
                                label: appStrings.editPersonalInformation,
                                onPressed: _openPersonalInfoSheet,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _ProfileListCard(
                          children: [
                            _ProfileMenuRow(
                              icon: Icons.fitness_center_rounded,
                              title: appStrings.profileTraining,
                              onTap: () => context.push('/training'),
                            ),
                            _ProfileMenuRow(
                              icon: Icons.workspace_premium_outlined,
                              title: appStrings.profileMembership,
                              onTap: () => context.push('/membership'),
                            ),
                            _ProfileMenuRow(
                              icon: Icons.settings_outlined,
                              title: appStrings.profileSettings,
                              onTap: () => context.push('/settings'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (_appVersion.isNotEmpty) ...[
                          Center(
                            child: Text(
                              'ATHLETE615 · $_appVersion',
                              style: _ProfileText.subtle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlowCondensed(
      color: const Color(0xFFB8BDC7),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    filled: true,
    fillColor: const Color(0xFFF4F5F7),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
  );
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

  static TextStyle sectionTitle = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.8,
    height: 1.0,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.3,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABABAB),
    letterSpacing: 0.3,
    height: 1.0,
  );

  static TextStyle input = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
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
      color: const Color(0xFF171717),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
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
                        18,
                        weight: FontWeight.w800,
                        color: Colors.white,
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
                        24,
                        weight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4,
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
                              Icons.notifications_outlined,
                              size: 28,
                              color: Color(0xFFB59B6A),
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
                                  color: Color(0xFFB42318),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  unreadNotifications > 99
                                      ? '99+'
                                      : unreadNotifications.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
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
      borderRadius: BorderRadius.circular(18),
      onTap: uploading ? null : onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              color: const Color(0xFFF7F3EA),
              child: hasAvatar
                  ? Image.network(
                      avatarUrl!,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                    )
                  : Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'A',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFB59B6A),
                        height: 1.0,
                      ),
                    ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFFB59B6A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF171717), width: 2),
              ),
              child: uploading
                  ? const Padding(
                      padding: EdgeInsets.all(5),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt_rounded,
                      color: Color(0xFF111111),
                      size: 12,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF323232), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(), style: _ProfileText.subtle),
          ),
          const SizedBox(width: 12),
          Text(value, style: _ProfileText.body),
        ],
      ),
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
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF323232), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const color = Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF323232)),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFFB59B6A)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: -0.1,
                  height: 1.0,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 24,
              color: Color(0xFFABABAB),
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
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF323232), width: 1),
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
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
