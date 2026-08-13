import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPreferences {
  const NotificationPreferences({
    required this.communicationsPushEnabled,
    required this.notificationsPushEnabled,
  });

  const NotificationPreferences.defaults()
    : communicationsPushEnabled = true,
      notificationsPushEnabled = true;

  final bool communicationsPushEnabled;
  final bool notificationsPushEnabled;
}

abstract interface class NotificationPreferencesRepository {
  Future<NotificationPreferences> loadPreferences();
  Future<NotificationPreferences> updateCommunications(bool enabled);
  Future<NotificationPreferences> updateNotifications(bool enabled);
}

class SupabaseNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  SupabaseNotificationPreferencesRepository(this.client);

  final SupabaseClient client;

  @override
  Future<NotificationPreferences> loadPreferences() async {
    final userId = _userId;
    final row = await client
        .from('notification_preferences')
        .select('communications_push_enabled, notifications_push_enabled')
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? const NotificationPreferences.defaults() : _parse(row);
  }

  @override
  Future<NotificationPreferences> updateCommunications(bool enabled) async {
    final current = await loadPreferences();
    return _upsert(
      NotificationPreferences(
        communicationsPushEnabled: enabled,
        notificationsPushEnabled: current.notificationsPushEnabled,
      ),
    );
  }

  @override
  Future<NotificationPreferences> updateNotifications(bool enabled) async {
    final current = await loadPreferences();
    return _upsert(
      NotificationPreferences(
        communicationsPushEnabled: current.communicationsPushEnabled,
        notificationsPushEnabled: enabled,
      ),
    );
  }

  Future<NotificationPreferences> _upsert(
    NotificationPreferences preferences,
  ) async {
    final row = await client
        .from('notification_preferences')
        .upsert({
          'user_id': _userId,
          'communications_push_enabled': preferences.communicationsPushEnabled,
          'notifications_push_enabled': preferences.notificationsPushEnabled,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id')
        .select('communications_push_enabled, notifications_push_enabled')
        .single();
    return _parse(row);
  }

  String get _userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('User is not authenticated.');
    return id;
  }

  NotificationPreferences _parse(Map<String, dynamic> row) =>
      NotificationPreferences(
        communicationsPushEnabled: row['communications_push_enabled'] != false,
        notificationsPushEnabled: row['notifications_push_enabled'] != false,
      );
}
