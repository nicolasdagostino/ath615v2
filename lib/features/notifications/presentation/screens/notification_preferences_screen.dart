import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';
import '../../data/notification_preferences_repository.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key, this.repository});

  final NotificationPreferencesRepository? repository;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  late final NotificationPreferencesRepository _repository =
      widget.repository ??
      SupabaseNotificationPreferencesRepository(Supabase.instance.client);
  NotificationPreferences? _preferences;
  bool _loading = true;
  bool _savingCommunications = false;
  bool _savingNotifications = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final preferences = await _repository.loadPreferences();
      if (mounted) setState(() => _preferences = preferences);
    } catch (_) {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setCommunications(bool enabled) async {
    if (_savingCommunications || _preferences == null) return;
    setState(() => _savingCommunications = true);
    try {
      final saved = await _repository.updateCommunications(enabled);
      if (mounted) setState(() => _preferences = saved);
    } catch (_) {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _savingCommunications = false);
    }
  }

  Future<void> _setNotifications(bool enabled) async {
    if (_savingNotifications || _preferences == null) return;
    setState(() => _savingNotifications = true);
    try {
      final saved = await _repository.updateNotifications(enabled);
      if (mounted) setState(() => _preferences = saved);
    } catch (_) {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _savingNotifications = false);
    }
  }

  void _showError() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(appStrings.notificationPreferencesSaveError)),
  );

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Column(
          children: [
            AppSecondaryActionHeader(
              title: appStrings.personalNotifications,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: _loading
                  ? const AppCenteredLoadingIndicator()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenX,
                        AppSpacing.lg,
                        AppSpacing.screenX,
                        AppSpacing.xl,
                      ),
                      children: [
                        _PreferenceRow(
                          key: const ValueKey('communications-push-switch'),
                          title: appStrings.gymCommunicationsPreference,
                          description:
                              appStrings.gymCommunicationsPreferenceDescription,
                          value: preferences?.communicationsPushEnabled ?? true,
                          saving: _savingCommunications,
                          onChanged: _setCommunications,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Divider(color: AppColors.border(context), height: 1),
                        const SizedBox(height: AppSpacing.lg),
                        _PreferenceRow(
                          key: const ValueKey('notifications-push-switch'),
                          title: appStrings.personalNotifications,
                          description:
                              appStrings.notificationsPreferenceDescription,
                          value: preferences?.notificationsPushEnabled ?? true,
                          saving: _savingNotifications,
                          onChanged: _setNotifications,
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

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.saving,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: AppTypography.itemTitle(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(description, style: AppTypography.bodySecondary(context)),
          ],
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      saving
          ? const SizedBox(
              width: AppSizes.minimumTouchTarget,
              height: AppSizes.minimumTouchTarget,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
            )
          : Switch(
              value: value,
              activeThumbColor: AppColors.primary,
              onChanged: onChanged,
            ),
    ],
  );
}
