import 'package:flutter/material.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_outlined_button.dart';
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
  String? _gymId;

  AuthRepository get _repo => AuthRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
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
        ],
      ),
    );
  }
}
