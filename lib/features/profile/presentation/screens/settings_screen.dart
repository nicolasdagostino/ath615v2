import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/data/auth_repository.dart';

Color _profileHubBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF252525) : const Color(0xFFF1F2F4);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  @override
  void dispose() {
    _gymName.dispose();
    super.dispose();
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
              margin: const EdgeInsets.all(AppSpacing.sheetMargin),
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(AppRadii.panel),
                border: Border.all(color: AppColors.border(context), width: 1),
                boxShadow: AppShadows.card(context),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appStrings.profileGymName.toUpperCase(),
                    style: _SettingsText.sectionTitle,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _gymName,
                    cursorColor: AppColors.accent,
                    style: _SettingsText.input.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _inputDecoration(
                      context,
                      appStrings.profileGymName,
                    ),
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

  @override
  Widget build(BuildContext context) {
    final role = _profile?['role']?.toString();
    final canEditGym = role == 'admin' || role == 'owner';

    return Scaffold(
      backgroundColor: _profileHubBackground(context),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
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
                    'Settings',
                    style: _SettingsText.header.copyWith(
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            _SettingsMenuSection(
              children: [
                _SettingsListCard(
                  children: [
                    _SettingsMenuRow(
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
                const SizedBox(height: 12),
                _SettingsListCard(
                  children: [
                    _SettingsMenuRow(
                      title:
                          '${appStrings.appearance} · ${themeController.isDark ? appStrings.dark : appStrings.light}',
                      onTap: () async {
                        await themeController.toggle();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                if (canEditGym) ...[
                  const SizedBox(height: 34),
                  _SettingsListCard(
                    children: [
                      _SettingsMenuRow(
                        title: appStrings.profileGymName,
                        onTap: _openGymNameSheet,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
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

class _SettingsText {
  const _SettingsText._();

  static TextStyle header = GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle sectionTitle = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.8,
    height: 1.0,
  );

  static TextStyle input = GoogleFonts.barlowCondensed(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}

class _SettingsMenuSection extends StatelessWidget {
  const _SettingsMenuSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      color: _profileHubBackground(context),
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 72),
      child: Column(children: children),
    );
  }
}

class _SettingsListCard extends StatelessWidget {
  const _SettingsListCard({required this.children});

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

class _SettingsMenuRow extends StatelessWidget {
  const _SettingsMenuRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.textPrimary(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
