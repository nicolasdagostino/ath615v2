import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_control_styles.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../../../auth/data/auth_repository.dart';

class JoinGymScreen extends StatefulWidget {
  const JoinGymScreen({super.key});

  @override
  State<JoinGymScreen> createState() => _JoinGymScreenState();
}

class _JoinGymScreenState extends State<JoinGymScreen> {
  final _code = TextEditingController();
  final _phone = TextEditingController();
  final _birthDate = TextEditingController();

  Uint8List? _avatarBytes;

  Map<String, dynamic>? _gym;
  bool _loading = false;
  bool _requestSent = false;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadPendingRequest();
  }

  Future<void> _loadPendingRequest() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final request = await _client
          .from('gym_join_requests')
          .select('gym_id, gyms(id, name, logo_url, address, gym_code)')
          .eq('user_id', user.id)
          .eq('status', 'pending')
          .maybeSingle();

      if (!mounted || request == null) return;

      final gym = request['gyms'];

      if (gym is Map<String, dynamic>) {
        setState(() {
          _gym = gym;
          _requestSent = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _code.dispose();
    _phone.dispose();
    _birthDate.dispose();
    super.dispose();
  }

  String get _normalizedCode => _code.text.trim().toUpperCase();

  bool get _canSendRequest {
    return _gym != null &&
        _phone.text.trim().length >= 6 &&
        _birthDate.text.trim().isNotEmpty &&
        !_loading;
  }

  String _dateInputValue(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return '${date.day}/${date.month}/${date.year}';
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
    setState(() => _birthDate.text = _dateInputValue(picked));
  }

  Future<String?> _uploadAvatar(String userId) async {
    final bytes = _avatarBytes;
    if (bytes == null) return null;

    final path = '$userId.jpg';

    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    final publicUrl = _client.storage.from('avatars').getPublicUrl(path);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _updateProfile(String userId, {String? avatarUrl}) async {
    final payload = <String, dynamic>{
      'phone': _phone.text.trim(),
      'birth_date': _birthDate.text.trim(),
    };

    if (avatarUrl != null) {
      payload['avatar_url'] = avatarUrl;
    }

    await _client.from('profiles').update(payload).eq('id', userId);
  }

  Future<void> _pickAvatar() async {
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

    final bytes = await cropped.readAsBytes();
    if (!mounted) return;
    setState(() => _avatarBytes = bytes);
  }

  Future<void> _findGym() async {
    if (_normalizedCode.isEmpty) return;

    setState(() {
      _loading = true;
      _gym = null;
    });

    try {
      final gym = await _client
          .from('gyms')
          .select('id, name, logo_url, address, gym_code')
          .ilike('gym_code', _normalizedCode)
          .maybeSingle();

      if (!mounted) return;

      if (gym == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appStrings.gymCodeNotFound)));
      }

      setState(() {
        _gym = gym;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.joinGymError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendJoinRequest({
    required String userId,
    required String gymId,
  }) async {
    await _client.from('gym_join_requests').insert({
      'user_id': userId,
      'gym_id': gymId,
      'status': 'pending',
    });
  }

  Future<void> _requestJoin() async {
    final user = _client.auth.currentUser;
    final gym = _gym;
    final gymId = gym?['id']?.toString();

    if (user == null || gymId == null) return;

    setState(() => _loading = true);

    try {
      await _updateProfile(user.id);
      final avatarUrl = await _uploadAvatar(user.id);
      await _updateProfile(user.id, avatarUrl: avatarUrl);
      await _sendJoinRequest(userId: user.id, gymId: gymId);

      if (!mounted) return;
      setState(() => _requestSent = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.joinGymError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canFind = _normalizedCode.isNotEmpty && !_loading;
    final gym = _gym;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(AppSpacing.screenX),
          children: [
            Text(
              appStrings.appBrand,
              style: GoogleFonts.barlowCondensed(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary(context),
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appStrings.joinGymSubtitle,
              style: GoogleFonts.barlowCondensed(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: _requestSent
                  ? _PendingApprovalCard(gymName: gym?['name']?.toString())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appStrings.joinGymTitle.toUpperCase(),
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary(context),
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          appStrings.joinGymMessage,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary(context),
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _code,
                          onChanged: (_) {
                            setState(() {
                              _gym = null;
                            });
                          },
                          textCapitalization: TextCapitalization.characters,
                          cursorColor: AppColors.accent,
                          style: AppTypography.itemTitle(context),
                          decoration: AppControlStyles.input(
                            context,
                            hintText: appStrings.gymCode,
                            prefixIcon: Icon(
                              Icons.qr_code_2_rounded,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        AppButton(
                          label: appStrings.findGym,
                          loading: _loading && gym == null,
                          onPressed: canFind ? _findGym : null,
                        ),
                        if (gym != null) ...[
                          const SizedBox(height: 18),
                          _GymResultCard(gym: gym),
                          const SizedBox(height: 14),
                          Center(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: _loading ? null : _pickAvatar,
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 42,
                                    backgroundColor: AppColors.surfaceAlt(
                                      context,
                                    ),
                                    backgroundImage: _avatarBytes == null
                                        ? null
                                        : MemoryImage(_avatarBytes!),
                                    child: _avatarBytes == null
                                        ? const Icon(
                                            Icons.add_a_photo_outlined,
                                            color: AppColors.accent,
                                            size: 28,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    appStrings.addProfilePhoto,
                                    style: GoogleFonts.barlowCondensed(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            appStrings.completeProfile.toUpperCase(),
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            onChanged: (_) => setState(() {}),
                            cursorColor: AppColors.accent,
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary(context),
                            ),
                            decoration: _joinInput(
                              context,
                              appStrings.authPhone,
                              Icons.phone_outlined,
                            ),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: _pickBirthDate,
                            child: InputDecorator(
                              decoration: _joinInput(
                                context,
                                appStrings.authBirthDate,
                                Icons.calendar_month_rounded,
                              ),
                              child: Text(
                                _birthDate.text.trim().isEmpty
                                    ? appStrings.authBirthDate
                                    : _formatDate(_birthDate.text),
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: _birthDate.text.trim().isEmpty
                                      ? AppColors.textSecondary(context)
                                      : AppColors.textPrimary(context),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          AppButton(
                            label: appStrings.sendRequest,
                            loading: _loading,
                            onPressed: _canSendRequest ? _requestJoin : null,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton.icon(
                            onPressed: _loading
                                ? null
                                : () async {
                                    final code = await context.push<String>(
                                      '/scan-gym-qr',
                                    );

                                    if (code == null || code.trim().isEmpty) {
                                      return;
                                    }

                                    _code.text = code.trim().toUpperCase();
                                    await _findGym();
                                  },
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: Text(appStrings.scanGymQr),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: _loading
                  ? null
                  : () async {
                      await AuthRepository(_client).signOut();
                      if (!context.mounted) return;
                      context.go('/login');
                    },
              child: Text(appStrings.logout),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _joinInput(BuildContext context, String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    prefixIcon: Icon(icon, color: AppColors.textSecondary(context)),
    filled: true,
    fillColor: AppColors.surfaceAlt(context),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
  );
}

class _GymResultCard extends StatelessWidget {
  const _GymResultCard({required this.gym});

  final Map<String, dynamic> gym;

  @override
  Widget build(BuildContext context) {
    final logoUrl = gym['logo_url']?.toString();
    final name = gym['name']?.toString() ?? appStrings.defaultGymName;
    final address = gym['address']?.toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.surface(context),
            backgroundImage: logoUrl != null && logoUrl.isNotEmpty
                ? NetworkImage(logoUrl)
                : null,
            child: logoUrl == null || logoUrl.isEmpty
                ? const Icon(
                    Icons.fitness_center_rounded,
                    color: AppColors.accent,
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                if (address != null && address.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    address,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.accent),
        ],
      ),
    );
  }
}

class _PendingApprovalCard extends StatelessWidget {
  const _PendingApprovalCard({required this.gymName});

  final String? gymName;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(
          Icons.hourglass_top_rounded,
          size: 42,
          color: AppColors.accent,
        ),
        const SizedBox(height: 14),
        Text(
          appStrings.joinRequestSent.toUpperCase(),
          textAlign: TextAlign.center,
          style: GoogleFonts.barlowCondensed(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          appStrings.joinRequestPendingMessage(
            gymName ?? appStrings.defaultGymName,
          ),
          textAlign: TextAlign.center,
          style: GoogleFonts.barlowCondensed(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary(context),
            height: 1.25,
          ),
        ),
      ],
    );
  }
}
