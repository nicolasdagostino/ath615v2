import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';

class JoinGymScreen extends StatefulWidget {
  const JoinGymScreen({super.key});

  @override
  State<JoinGymScreen> createState() => _JoinGymScreenState();
}

class _JoinGymScreenState extends State<JoinGymScreen> {
  final _code = TextEditingController();

  Map<String, dynamic>? _gym;
  bool _loading = false;
  bool _requestSent = false;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _normalizedCode => _code.text.trim().toUpperCase();

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

  Future<void> _requestJoin() async {
    final user = _client.auth.currentUser;
    final gym = _gym;
    if (user == null || gym == null) return;

    setState(() => _loading = true);

    try {
      await _client.from('gym_join_requests').insert({
        'user_id': user.id,
        'gym_id': gym['id'],
        'status': 'pending',
      });

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
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
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
                borderRadius: BorderRadius.circular(28),
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
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(context),
                          ),
                          decoration: InputDecoration(
                            hintText: appStrings.gymCode,
                            labelText: appStrings.gymCode,
                            prefixIcon: Icon(
                              Icons.qr_code_2_rounded,
                              color: AppColors.textSecondary(context),
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceAlt(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
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
                          AppButton(
                            label: appStrings.joinGym,
                            loading: _loading,
                            onPressed: _loading ? null : _requestJoin,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: Text(appStrings.scanQrComingSoon),
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
                      await _client.auth.signOut();
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
