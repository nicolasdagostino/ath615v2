import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/data/auth_repository.dart';
import 'attendance_history_screen.dart';

class ProfileOverviewData {
  const ProfileOverviewData({
    required this.profile,
    required this.gym,
    required this.attendances,
  });

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? gym;
  final List<ProfileAttendance> attendances;
}

List<Map<String, dynamic>> confirmedAttendanceRows(
  Iterable<Map<String, dynamic>> rows,
) => rows
    .where((row) => row['status']?.toString() == 'attended')
    .toList(growable: false);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.gymName,
    required this.onGymNameChanged,
    required this.unreadNotifications,
    required this.onOpenNotifications,
    this.dataLoaderForTesting,
  });

  final String? gymName;
  final Future<void> Function() onGymNameChanged;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  @visibleForTesting
  final Future<ProfileOverviewData> Function()? dataLoaderForTesting;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  bool _uploadingAvatar = false;
  ProfileOverviewData? _data;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<ProfileOverviewData> _loadOverview() async {
    final profile = await _repo.myProfile();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final gymId = profile?['gym_id']?.toString();

    Map<String, dynamic>? gym;
    if (gymId != null && gymId.isNotEmpty) {
      try {
        gym = await Supabase.instance.client
            .from('gyms')
            .select('name, logo_url')
            .eq('id', gymId)
            .maybeSingle();
      } catch (_) {}
    }

    final attendances = <ProfileAttendance>[];
    if (userId != null) {
      try {
        final rows = await Supabase.instance.client
            .from('class_bookings')
            .select('id, status, classes(title, starts_at)')
            .eq('user_id', userId)
            .eq('status', 'attended');

        for (final row in confirmedAttendanceRows(
          List<Map<String, dynamic>>.from(rows),
        )) {
          final klass = row['classes'];
          if (klass is! Map) continue;
          final startsAt = DateTime.tryParse(
            klass['starts_at']?.toString() ?? '',
          )?.toLocal();
          if (startsAt != null) {
            attendances.add(
              ProfileAttendance(
                startsAt: startsAt,
                className:
                    klass['title']?.toString() ?? appStrings.classFallback,
              ),
            );
          }
        }
      } catch (_) {}
    }

    return ProfileOverviewData(
      profile: profile,
      gym: gym,
      attendances: attendances,
    );
  }

  Future<void> _load() async {
    final data = await (widget.dataLoaderForTesting?.call() ?? _loadOverview());
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
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
          hideBottomControls: false,
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
    body: _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        : ProfileOverview(
            data: _data!,
            fallbackGymName: widget.gymName,
            uploadingAvatar: _uploadingAvatar,
            onAvatarTap: _uploadAvatar,
            onSettings: () => context.push('/settings'),
            onMemberships: () => context.push('/membership'),
            onRecords: () => context.push('/records'),
            onAttendanceHistory: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    AttendanceHistoryScreen(attendances: _data!.attendances),
              ),
            ),
          ),
  );
}

class ProfileOverview extends StatelessWidget {
  const ProfileOverview({
    super.key,
    required this.data,
    required this.fallbackGymName,
    required this.uploadingAvatar,
    required this.onAvatarTap,
    required this.onSettings,
    required this.onMemberships,
    required this.onRecords,
    required this.onAttendanceHistory,
    this.nowForTesting,
  });

  final ProfileOverviewData data;
  final String? fallbackGymName;
  final bool uploadingAvatar;
  final VoidCallback onAvatarTap;
  final VoidCallback onSettings;
  final VoidCallback onMemberships;
  final VoidCallback onRecords;
  final VoidCallback onAttendanceHistory;
  final DateTime? nowForTesting;

  String get _displayName {
    final name = data.profile?['full_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'ATHLETE615 Member' : name;
  }

  String get _gymName {
    final name = data.gym?['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final fallback = fallbackGymName?.trim() ?? '';
    return fallback.isEmpty ? appStrings.appBrand : fallback;
  }

  int _countWhere(bool Function(DateTime date) predicate) =>
      data.attendances.map((item) => item.startsAt).where(predicate).length;

  @override
  Widget build(BuildContext context) {
    final now = nowForTesting ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final week = _countWhere(
      (date) => !date.isBefore(weekStart) && date.isBefore(weekEnd),
    );
    final month = _countWhere(
      (date) => date.year == now.year && date.month == now.month,
    );
    final year = _countWhere((date) => date.year == now.year);
    final total = data.attendances.length;

    return Column(
      children: [
        _ProfileFixedHero(
          displayName: _displayName,
          avatarUrl: data.profile?['avatar_url']?.toString(),
          uploadingAvatar: uploadingAvatar,
          onAvatarTap: onAvatarTap,
          onSettings: onSettings,
        ),
        Expanded(
          child: ColoredBox(
            key: const ValueKey('profile-scroll-viewport'),
            color: AppColors.background(context),
            child: ListView(
              key: const ValueKey('profile-overview-scroll'),
              clipBehavior: Clip.hardEdge,
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenX,
                    AppSpacing.md,
                    AppSpacing.screenX,
                    104,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GymIdentity(name: _gymName),
                      const SizedBox(height: AppSpacing.sm),
                      _CompactProfileAction(
                        key: const ValueKey('profile-records-action'),
                        icon: Icons.emoji_events_outlined,
                        title: appStrings.personalRecords,
                        onTap: onRecords,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _MilestoneCard(
                        attendedCount: total,
                        displayName: _displayName,
                        avatarUrl: data.profile?['avatar_url']?.toString(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickAction(
                              key: const ValueKey(
                                'profile-membership-card-disabled',
                              ),
                              icon: Icons.qr_code_2_rounded,
                              title: appStrings.pick(
                                'Membership card',
                                'Tarjeta de membresía',
                              ),
                              subtitle: appStrings.comingSoon,
                              enabled: false,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _QuickAction(
                              key: const ValueKey('profile-memberships-action'),
                              icon: Icons.card_membership_rounded,
                              title: appStrings.myMemberships,
                              enabled: true,
                              onTap: onMemberships,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              appStrings.pick('ATTENDANCE', 'ASISTENCIA'),
                              style: AppTypography.sectionTitle(context),
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('profile-attendance-view-all'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              minimumSize: const Size(44, 44),
                            ),
                            onPressed: onAttendanceHistory,
                            child: Text(
                              appStrings.pick('VIEW ALL', 'VER TODO'),
                              style: AppTypography.buttonLabel(
                                context,
                              ).copyWith(color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _AttendanceGrid(
                        week: week,
                        month: month,
                        year: year,
                        total: total,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileFixedHero extends StatelessWidget {
  const _ProfileFixedHero({
    required this.displayName,
    required this.avatarUrl,
    required this.uploadingAvatar,
    required this.onAvatarTap,
    required this.onSettings,
  });

  final String displayName;
  final String? avatarUrl;
  final bool uploadingAvatar;
  final VoidCallback onAvatarTap;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('profile-fixed-hero'),
    color: AppColors.background(context),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ProfilePrimaryHeader(),
        SizedBox(
          height: _ProfileAvatarOverlap.avatarSize / 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
            child: OverflowBox(
              minHeight: _ProfileAvatarOverlap.avatarSize,
              maxHeight: _ProfileAvatarOverlap.avatarSize,
              alignment: Alignment.bottomLeft,
              child: _ProfileAvatar(
                displayName: displayName,
                avatarUrl: avatarUrl,
                uploading: uploadingAvatar,
                onTap: onAvatarTap,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            AppSpacing.sm,
            AppSpacing.screenX,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  key: const ValueKey('profile-display-name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(context),
                    height: 1.02,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SettingsButton(onTap: onSettings),
            ],
          ),
        ),
      ],
    ),
  );
}

class ProfilePrimaryHeader extends StatelessWidget {
  const ProfilePrimaryHeader({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: AppColors.primary,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
    child: SizedBox(
      key: const ValueKey('profile-primary-header'),
      width: double.infinity,
      child: const ColoredBox(
        color: AppColors.primary,
        child: SafeArea(
          bottom: false,
          child: SizedBox(height: AppSizes.mainHeaderHeight),
        ),
      ),
    ),
  );
}

class _ProfileAvatarOverlap {
  static const avatarSize = 112.0;
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
    final initials = displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Semantics(
      button: true,
      label: appStrings.updatePhoto,
      child: InkWell(
        key: const ValueKey('profile-avatar'),
        customBorder: const CircleBorder(),
        onTap: uploading ? null : onTap,
        child: Container(
          width: 112,
          height: 112,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface(context),
            boxShadow: AppShadows.soft(context),
          ),
          child: ClipOval(
            child: ColoredBox(
              color: AppColors.surfaceAlt(context),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasAvatar)
                    Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _AvatarInitials(initials),
                    )
                  else
                    _AvatarInitials(initials),
                  if (uploading)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.28),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials(this.initials);
  final String initials;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      initials.isEmpty ? 'A' : initials,
      key: const ValueKey('profile-avatar-fallback'),
      style: GoogleFonts.barlowCondensed(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.primary,
      ),
    ),
  );
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: appStrings.profileSettings,
    child: InkWell(
      key: const ValueKey('profile-settings-button'),
      borderRadius: BorderRadius.circular(AppRadii.input),
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.input),
          border: Border.all(color: AppColors.border(context)),
          color: AppColors.surface(context),
        ),
        child: Icon(
          CupertinoIcons.gear,
          color: AppColors.textPrimary(context),
          size: 22,
        ),
      ),
    ),
  );
}

class _GymIdentity extends StatelessWidget {
  const _GymIdentity({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('profile-gym-identity'),
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 64),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(color: AppColors.border(context)),
    ),
    child: Column(
      key: const ValueKey('profile-gym-content'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          appStrings.gymIdentityLabel,
          key: const ValueKey('profile-gym-label'),
          style: AppTypography.helper(context).copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          name.toUpperCase(),
          key: const ValueKey('profile-gym-name'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.itemTitle(context),
        ),
      ],
    ),
  );
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.attendedCount,
    required this.displayName,
    required this.avatarUrl,
  });

  final int attendedCount;
  final String displayName;
  final String? avatarUrl;

  int get target {
    for (final value in [50, 100, 200, 500]) {
      if (attendedCount < value) return value;
    }
    return 500;
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (target - attendedCount).clamp(0, target);
    final progress = (attendedCount / target).clamp(0.0, 1.0);
    return Container(
      key: const ValueKey('profile-milestone'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.pick('NEXT MILESTONE', 'PRÓXIMO MILESTONE'),
            style: AppTypography.sectionTitle(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _MilestoneAvatar(displayName: displayName, avatarUrl: avatarUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$attendedCount / $target',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      child: LinearProgressIndicator(
                        key: const ValueKey('profile-milestone-progress'),
                        value: progress,
                        minHeight: 9,
                        color: AppColors.primary,
                        backgroundColor: AppColors.surfaceAlt(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            appStrings.pick(
              '$remaining classes to reach $target',
              '$remaining clases para llegar a $target',
            ),
            style: AppTypography.bodySecondary(context),
          ),
        ],
      ),
    );
  }
}

class _MilestoneAvatar extends StatelessWidget {
  const _MilestoneAvatar({required this.displayName, required this.avatarUrl});
  final String displayName;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isEmpty ? 'A' : displayName[0].toUpperCase();
    final valid = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      foregroundImage: valid ? NetworkImage(avatarUrl!) : null,
      child: valid
          ? null
          : Text(
              initial,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    super.key,
    required this.icon,
    required this.title,
    required this.enabled,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final bool enabled;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? AppColors.textPrimary(context)
        : AppColors.muted(context);
    return Semantics(
      button: enabled,
      enabled: enabled,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: enabled ? onTap : null,
        child: Container(
          height: 144,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.surface(context)
                : AppColors.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: enabled ? AppColors.primary : foreground,
                size: 26,
              ),
              const Spacer(),
              Text(
                title.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.itemTitle(
                  context,
                ).copyWith(color: foreground),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle!,
                  style: AppTypography.bodySecondary(
                    context,
                  ).copyWith(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactProfileAction extends StatelessWidget {
  const _CompactProfileAction({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface(context),
    borderRadius: BorderRadius.circular(AppRadii.card),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.itemTitle(context),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ],
        ),
      ),
    ),
  );
}

class _AttendanceGrid extends StatelessWidget {
  const _AttendanceGrid({
    required this.week,
    required this.month,
    required this.year,
    required this.total,
  });

  final int week;
  final int month;
  final int year;
  final int total;

  @override
  Widget build(BuildContext context) => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2,
    mainAxisSpacing: AppSpacing.sm,
    crossAxisSpacing: AppSpacing.sm,
    childAspectRatio: 1.45,
    children: [
      _AttendanceStat(
        key: const ValueKey('profile-attendance-week'),
        label: appStrings.pick('Week', 'Semana'),
        value: week,
      ),
      _AttendanceStat(
        key: const ValueKey('profile-attendance-month'),
        label: appStrings.pick('Month', 'Mes'),
        value: month,
      ),
      _AttendanceStat(
        key: const ValueKey('profile-attendance-year'),
        label: appStrings.pick('Year', 'Año'),
        value: year,
      ),
      _AttendanceStat(
        key: const ValueKey('profile-attendance-total'),
        label: appStrings.pick('All time', 'Histórico'),
        value: total,
      ),
    ],
  );
}

class _AttendanceStat extends StatelessWidget {
  const _AttendanceStat({super.key, required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(color: AppColors.border(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySecondary(context),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '$value',
          style: GoogleFonts.barlowCondensed(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary(context),
            height: 1,
          ),
        ),
      ],
    ),
  );
}
