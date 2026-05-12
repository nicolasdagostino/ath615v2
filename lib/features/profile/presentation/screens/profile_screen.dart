import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/data/auth_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _password = TextEditingController();
  final _gymName = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _birthDate = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _membership;
  List<Map<String, dynamic>> _creditLogs = [];
  int _attendedCount = 0;
  String? _gymId;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
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

    final picked = await showDatePicker(
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

  String _creditReasonLabel(String reason) {
    if (reason == 'assigned') return appStrings.assigned;
    if (reason == 'booked') return appStrings.booked;
    if (reason == 'cancelled') return appStrings.cancelled;
    return reason;
  }

  Future<void> _loadStats(String userId) async {
    final attended = await Supabase.instance.client
        .from('class_bookings')
        .select('id')
        .eq('user_id', userId)
        .eq('status', 'attended');

    _attendedCount = List<Map<String, dynamic>>.from(attended).length;
  }

  Future<void> _loadMembership(String userId) async {
    final membership = await Supabase.instance.client
        .from('member_memberships')
        .select(
          'id, credits_remaining, expires_at, membership_plans(name, plan_type)',
        )
        .eq('user_id', userId)
        .eq('is_active', true)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .maybeSingle();

    final logs = await Supabase.instance.client
        .from('membership_credit_logs')
        .select('amount, reason, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(8);

    _membership = membership;
    _creditLogs = List<Map<String, dynamic>>.from(logs);
  }

  Future<void> _load() async {
    final profile = await _repo.myProfile();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final gymId = profile?['gym_id'] as String?;

    if (userId != null) {
      await _loadMembership(userId);
      await _loadStats(userId);
    }

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
      _gymId = gymId;
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
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
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
                  Text(title.toUpperCase(), style: _ProfileConfirmText.title),
                  const SizedBox(height: 10),
                  Text(message, style: _ProfileConfirmText.body),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileConfirmSecondaryButton(
                          label: appStrings.cancel,
                          onTap: () => Navigator.pop(context, false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: danger
                            ? _ProfileConfirmDangerButton(
                                label: confirmLabel,
                                onTap: () => Navigator.pop(context, true),
                              )
                            : _ProfileConfirmPrimaryButton(
                                label: confirmLabel,
                                onTap: () => Navigator.pop(context, true),
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

    return result == true;
  }

  Future<void> _openChangePasswordSheet() async {
    _password.clear();

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appStrings.profileChangePassword.toUpperCase(),
                    style: _ProfileText.sectionTitle,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    style: _ProfileText.input,
                    decoration: _inputDecoration(appStrings.profileNewPassword),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: appStrings.profileChangePassword,
                    loading: _loading,
                    onPressed: () async {
                      final navigator = Navigator.of(sheetContext);
                      await _changePassword();
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

  Future<void> _openGymNameSheet() async {
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appStrings.profileGymName.toUpperCase(),
                    style: _ProfileText.sectionTitle,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _gymName,
                    style: _ProfileText.input,
                    decoration: _inputDecoration(appStrings.profileGymName),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: appStrings.profileSaveGymName,
                    loading: _loading,
                    onPressed: () async {
                      final navigator = Navigator.of(sheetContext);
                      await _saveGymName();
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

  Future<void> _changePassword() async {
    setState(() => _loading = true);
    try {
      await _repo.updatePassword(_password.text);
      _password.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.passwordUpdated)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _saveGymName() async {
    final gymId = _gymId;
    final name = _gymName.text.trim();

    if (gymId == null || name.isEmpty) return;

    setState(() => _loading = true);

    try {
      await Supabase.instance.client
          .from('gyms')
          .update({'name': name})
          .eq('id', gymId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.gymNameUpdated)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.updateGymError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await _confirmAction(
      title: appStrings.profileLogout,
      message: appStrings.profileLogoutConfirm,
      confirmLabel: appStrings.profileLogout,
    );

    if (!confirmed) return;

    await _repo.signOut();
    if (!mounted) return;
    context.go('/login');
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
    final displayName = profileName.isNotEmpty ? profileName : email;
    final role = _profile?['role']?.toString();
    final canEditGym = role == 'admin' || role == 'owner';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _ProfileHeader(
              unreadNotifications: widget.unreadNotifications,
              onOpenNotifications: widget.onOpenNotifications,
            ),
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
                          Container(
                            width: 54,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F3EA),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
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
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(displayName, style: _ProfileText.title),
                                const SizedBox(height: 4),
                                Text(
                                  _displayRole(_profile?['role']?.toString()),
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
                    const SizedBox(height: 18),
                    _ProfileMilestoneCard(attendedCount: _attendedCount),
                    const SizedBox(height: 18),
                    _ProfileCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appStrings.membershipTitle.toUpperCase(),
                            style: _ProfileText.sectionTitle,
                          ),
                          const SizedBox(height: 14),
                          if (_membership == null)
                            Text(
                              appStrings.noActivePlan,
                              style: _ProfileText.body,
                            )
                          else ...[
                            _InfoRow(
                              label: appStrings.activePlan,
                              value:
                                  '${(_membership?['membership_plans'] as Map?)?['name'] ?? appStrings.plan}',
                            ),
                            _InfoRow(
                              label: appStrings.credits,
                              value:
                                  '${_membership?['credits_remaining'] ?? appStrings.unlimited}',
                            ),
                            _InfoRow(
                              label: appStrings.expires,
                              value: _formatDate(
                                _membership?['expires_at']?.toString(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Text(
                            appStrings.creditHistory.toUpperCase(),
                            style: _ProfileText.sectionTitle,
                          ),
                          const SizedBox(height: 10),
                          if (_creditLogs.isEmpty)
                            Text(
                              appStrings.noCreditHistory,
                              style: _ProfileText.subtle,
                            )
                          else ...[
                            _CreditLogSection(
                              title: appStrings.assignedCredits,
                              logs: _creditLogs
                                  .where((log) => log['reason'] == 'assigned')
                                  .toList(),
                              formatDate: _formatDate,
                              reasonLabel: _creditReasonLabel,
                            ),
                            _CreditLogSection(
                              title: appStrings.bookedCredits,
                              logs: _creditLogs
                                  .where((log) => log['reason'] == 'booked')
                                  .toList(),
                              formatDate: _formatDate,
                              reasonLabel: _creditReasonLabel,
                            ),
                            _CreditLogSection(
                              title: appStrings.cancelledCredits,
                              logs: _creditLogs
                                  .where((log) => log['reason'] == 'cancelled')
                                  .toList(),
                              formatDate: _formatDate,
                              reasonLabel: _creditReasonLabel,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ProfileListCard(
                      children: [
                        _ProfileMenuRow(
                          icon: Icons.language_rounded,
                          title:
                              '${appStrings.profileLanguage} · ${localeController.locale.languageCode.toUpperCase()}',
                          onTap: () {
                            final next =
                                localeController.locale.languageCode == 'en'
                                ? 'es'
                                : 'en';
                            localeController.setLanguage(next);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _ProfileListCard(
                      children: [
                        if (canEditGym)
                          _ProfileMenuRow(
                            icon: Icons.business_rounded,
                            title: appStrings.profileGymName,
                            onTap: _openGymNameSheet,
                          ),
                        _ProfileMenuRow(
                          icon: Icons.lock_outline_rounded,
                          title: appStrings.profileChangePassword,
                          onTap: _openChangePasswordSheet,
                        ),
                        _ProfileMenuRow(
                          icon: Icons.privacy_tip_outlined,
                          title: appStrings.profilePrivacyPolicy,
                          onTap: () => _openUrl('https://TU_URL_PRIVACY'),
                        ),
                        _ProfileMenuRow(
                          icon: Icons.description_outlined,
                          title: appStrings.profileTerms,
                          onTap: () => _openUrl('https://TU_URL_TERMS'),
                        ),
                        _ProfileMenuRow(
                          icon: Icons.help_outline_rounded,
                          title: appStrings.profileHelp,
                          onTap: () => _openUrl('https://TU_URL_HELP'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _ProfileListCard(
                      children: [
                        _ProfileMenuRow(
                          icon: Icons.logout_rounded,
                          title: appStrings.profileLogout,
                          onTap: _logout,
                        ),
                        _ProfileMenuRow(
                          icon: Icons.delete_outline_rounded,
                          title: appStrings.profileDeleteAccount,
                          danger: true,
                          onTap: _deleteAccount,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlowCondensed(
      color: const Color(0xFF8F96A3),
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
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle sectionTitle = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: 0.8,
    height: 1.0,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.3,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
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
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

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
      color: Colors.white,
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
                      appStrings.appBrand,
                      style: _font(
                        18,
                        weight: FontWeight.w800,
                        color: const Color(0xFF0E0E11),
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
                        18,
                        weight: FontWeight.w800,
                        color: const Color(0xFF0E0E11),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appStrings.profileHeaderSubtitle,
                      style: _font(
                        12,
                        weight: FontWeight.w500,
                        color: const Color(0xFF8F96A3),
                        letterSpacing: 0.3,
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
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F3EA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Badge(
                          isLabelVisible: unreadNotifications > 0,
                          label: Text(
                            unreadNotifications > 99
                                ? '99+'
                                : unreadNotifications.toString(),
                          ),
                          child: const Icon(
                            Icons.notifications_outlined,
                            size: 18,
                            color: Color(0xFFB59B6A),
                          ),
                        ),
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

class _ProfileMilestoneCard extends StatelessWidget {
  const _ProfileMilestoneCard({required this.attendedCount});

  final int attendedCount;

  int get _target {
    for (final target in [50, 100, 200, 500]) {
      if (attendedCount < target) return target;
    }
    return 500;
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final progress = target == 0
        ? 0.0
        : (attendedCount / target).clamp(0.0, 1.0);
    final remaining = (target - attendedCount).clamp(0, target);

    return _ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.milestone.toUpperCase(),
            style: _ProfileText.sectionTitle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$attendedCount / $target ${appStrings.classesAttended}',
                  style: _ProfileText.title,
                ),
              ),
              Text(
                '$remaining ${appStrings.classesToGo}',
                style: _ProfileText.subtle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: const Color(0xFFE8EAF0),
              color: const Color(0xFFB59B6A),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
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
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB42318) : const Color(0xFF0E0E11);

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8EAF0)),
              ),
              child: Icon(
                icon,
                size: 20,
                color: danger
                    ? const Color(0xFFB42318)
                    : const Color(0xFF8F96A3),
              ),
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
              color: Color(0xFF8F96A3),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (avatar) ...[
            Row(
              children: [
                const _SkeletonBox(width: 54, height: 54, radius: 18),
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
        color: const Color(0xFFE8EAF0),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _CreditLogSection extends StatelessWidget {
  const _CreditLogSection({
    required this.title,
    required this.logs,
    required this.formatDate,
    required this.reasonLabel,
  });

  final String title;
  final List<Map<String, dynamic>> logs;
  final String Function(String? raw) formatDate;
  final String Function(String reason) reasonLabel;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: _ProfileText.sectionTitle),
          const SizedBox(height: 6),
          ...logs.map((log) {
            final amount = log['amount'];
            final sign = (amount is int && amount > 0) ? '+' : '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$sign$amount · ${reasonLabel(log['reason']?.toString() ?? '')} · ${formatDate(log['created_at']?.toString())}',
                style: _ProfileText.subtle,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ProfileConfirmText {
  const _ProfileConfirmText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle rowTitle = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );
}

class _ProfileConfirmSecondaryButton extends StatelessWidget {
  const _ProfileConfirmSecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF384152),
          side: const BorderSide(color: Color(0xFFE1E4EA)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label.toUpperCase(), style: _ProfileConfirmText.rowTitle),
      ),
    );
  }
}

class _ProfileConfirmPrimaryButton extends StatelessWidget {
  const _ProfileConfirmPrimaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF111111),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _ProfileConfirmText.rowTitle.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _ProfileConfirmDangerButton extends StatelessWidget {
  const _ProfileConfirmDangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFB42318),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _ProfileConfirmText.rowTitle.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
