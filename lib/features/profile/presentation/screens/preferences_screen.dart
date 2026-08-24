import 'package:flutter/material.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/preferences/app_preferences_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  Future<void> _theme(ThemeMode value) async {
    await themeController.setThemeMode(value);
    if (mounted) setState(() {});
  }

  Future<void> _language(String value) async {
    await localeController.setLanguage(value);
    if (mounted) setState(() {});
  }

  Future<void> _time(AppTimeFormat value) async {
    await appPreferencesController.setTimeFormat(value);
    if (mounted) setState(() {});
  }

  Future<void> _units(AppUnitSystem value) async {
    await appPreferencesController.setUnitSystem(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: SafeArea(
      child: Column(
        children: [
          AppSecondaryActionHeader(
            title: appStrings.preferences,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('preferences-scroll'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                AppSpacing.sm,
                AppSpacing.screenX,
                AppSpacing.xl,
              ),
              children: [
                _PreferenceSection(
                  title: appStrings.appearance,
                  children: [
                    _ChoiceRow(
                      key: const ValueKey('preference-theme-light'),
                      label: appStrings.light,
                      selected: themeController.themeMode == ThemeMode.light,
                      onTap: () => _theme(ThemeMode.light),
                    ),
                    _ChoiceRow(
                      key: const ValueKey('preference-theme-dark'),
                      label: appStrings.dark,
                      selected: themeController.themeMode == ThemeMode.dark,
                      onTap: () => _theme(ThemeMode.dark),
                    ),
                    _ChoiceRow(
                      key: const ValueKey('preference-theme-system'),
                      label: appStrings.system,
                      selected: themeController.themeMode == ThemeMode.system,
                      onTap: () => _theme(ThemeMode.system),
                    ),
                  ],
                ),
                _PreferenceSection(
                  title: appStrings.profileLanguage,
                  children: [
                    _ChoiceRow(
                      key: const ValueKey('preference-language-es'),
                      label: 'Español',
                      selected: localeController.locale.languageCode == 'es',
                      onTap: () => _language('es'),
                    ),
                    _ChoiceRow(
                      key: const ValueKey('preference-language-en'),
                      label: 'English',
                      selected: localeController.locale.languageCode == 'en',
                      onTap: () => _language('en'),
                    ),
                  ],
                ),
                _PreferenceSection(
                  title: appStrings.timeFormat,
                  children: [
                    _ChoiceRow(
                      key: const ValueKey('preference-time-24'),
                      label: appStrings.twentyFourHours,
                      selected:
                          appPreferencesController.timeFormat ==
                          AppTimeFormat.twentyFourHour,
                      onTap: () => _time(AppTimeFormat.twentyFourHour),
                    ),
                    _ChoiceRow(
                      key: const ValueKey('preference-time-12'),
                      label: appStrings.twelveHours,
                      selected:
                          appPreferencesController.timeFormat ==
                          AppTimeFormat.twelveHour,
                      onTap: () => _time(AppTimeFormat.twelveHour),
                    ),
                  ],
                ),
                _PreferenceSection(
                  title: appStrings.units,
                  children: [
                    _ChoiceRow(
                      key: const ValueKey('preference-units-metric'),
                      label: appStrings.metric,
                      selected:
                          appPreferencesController.unitSystem ==
                          AppUnitSystem.metric,
                      onTap: () => _units(AppUnitSystem.metric),
                    ),
                    _ChoiceRow(
                      key: const ValueKey('preference-units-imperial'),
                      label: appStrings.imperial,
                      selected:
                          appPreferencesController.unitSystem ==
                          AppUnitSystem.imperial,
                      onTap: () => _units(AppUnitSystem.imperial),
                    ),
                  ],
                ),
                _PreferenceSection(
                  title: appStrings.pick('Calendar', 'Calendario'),
                  children: [
                    _ChoiceRow(
                      key: const ValueKey('preference-calendar-disabled'),
                      label: appStrings.syncCalendar,
                      selected: false,
                      enabled: false,
                      trailingLabel: appStrings.comingSoon,
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

class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xxs,
          ),
          child: Text(
            title.toUpperCase(),
            style: AppTypography.bodySecondary(
              context,
            ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.6),
          ),
        ),
        ...children,
      ],
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.enabled = true,
    this.trailingLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? AppColors.textPrimary(context)
        : AppColors.textSecondary(context).withValues(alpha: 0.65);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadii.input),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: AppTypography.body(
                  context,
                ).copyWith(color: foreground, fontWeight: FontWeight.w500),
              ),
            ),
            if (trailingLabel != null)
              Text(
                trailingLabel!,
                style: AppTypography.helper(
                  context,
                ).copyWith(color: foreground),
              )
            else
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary(context),
                size: 21,
              ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}
