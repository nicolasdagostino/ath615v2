import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_outlined_button.dart';
import '../../../../core/widgets/app_small_outlined_button.dart';
import '../../../auth/data/auth_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _password = TextEditingController();
  final _gymName = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _membership;
  List<Map<String, dynamic>> _creditLogs = [];
  String? _gymId;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.day}/${date.month}/${date.year}';
  }

  String _creditReasonLabel(String reason) {
    if (reason == 'assigned') return appStrings.assigned;
    if (reason == 'booked') return appStrings.booked;
    if (reason == 'cancelled') return appStrings.cancelled;
    return reason;
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
    });
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
    await _repo.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _deleteAccount() async {
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
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '-';
    final role = _profile?['role']?.toString();
    final canEditGym = role == 'admin' || role == 'owner';

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(email, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('${appStrings.profileRole}: ${_profile?['role'] ?? '-'}'),
          const SizedBox(height: 18),
          Text(
            appStrings.profileLanguage,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'en',
                label: Text(appStrings.profileEnglish),
              ),
              ButtonSegment(
                value: 'es',
                label: Text(appStrings.profileSpanish),
              ),
            ],
            selected: {localeController.locale.languageCode},
            onSelectionChanged: (values) {
              localeController.setLanguage(values.first);
              setState(() {});
            },
          ),

          const SizedBox(height: 24),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appStrings.membershipTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (_membership == null)
                  Text(appStrings.noActivePlan)
                else ...[
                  Text(
                    '${appStrings.activePlan}: ${(_membership?['membership_plans'] as Map?)?['name'] ?? appStrings.plan}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${appStrings.credits}: ${_membership?['credits_remaining'] ?? appStrings.unlimited}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${appStrings.expires}: ${_formatDate(_membership?['expires_at']?.toString())}',
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  appStrings.creditHistory,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (_creditLogs.isEmpty)
                  Text(appStrings.noCreditHistory)
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
          TextField(
            controller: _gymName,
            readOnly: !canEditGym,
            decoration: InputDecoration(labelText: appStrings.profileGymName),
          ),
          if (canEditGym) ...[
            const SizedBox(height: 12),
            AppButton(
              label: appStrings.profileSaveGymName,
              loading: _loading,
              onPressed: _saveGymName,
            ),
          ],
          const SizedBox(height: 32),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: appStrings.profileNewPassword,
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: appStrings.profileChangePassword,
            loading: _loading,
            onPressed: _changePassword,
          ),
          const SizedBox(height: 24),
          AppOutlinedButton(
            label: appStrings.profileLogout,
            onPressed: _logout,
          ),
          const SizedBox(height: 12),
          AppOutlinedButton(
            label: appStrings.profileDeleteAccount,
            onPressed: _deleteAccount,
          ),
          const SizedBox(height: 24),
          AppSmallOutlinedButton(
            label: appStrings.profilePrivacyPolicy,
            onPressed: () => _openUrl('https://TU_URL_PRIVACY'),
          ),
          const SizedBox(height: 10),
          AppSmallOutlinedButton(
            label: appStrings.profileTerms,
            onPressed: () => _openUrl('https://TU_URL_TERMS'),
          ),
          const SizedBox(height: 10),
          AppSmallOutlinedButton(
            label: appStrings.profileHelp,
            onPressed: () => _openUrl('https://TU_URL_HELP'),
          ),
        ],
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
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ...logs.map((log) {
            final amount = log['amount'];
            final sign = (amount is int && amount > 0) ? '+' : '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$sign$amount · ${reasonLabel(log['reason']?.toString() ?? '')} · ${formatDate(log['created_at']?.toString())}',
              ),
            );
          }),
        ],
      ),
    );
  }
}
