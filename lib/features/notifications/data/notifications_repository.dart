import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotificationRecord = Map<String, dynamic>;

abstract interface class NotificationsRepository {
  Future<List<NotificationRecord>> listOwn();
  Future<int> unreadCount();
  Future<bool> markRead(String notificationId);
  Future<int> markAllRead();
  Future<int> clearOwn();
}

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<NotificationRecord>> listOwn() async {
    final data = await _client.rpc('list_effective_notifications');
    if (data is! List) {
      throw const FormatException('Unexpected notifications response.');
    }
    return data
        .take(50)
        .map((row) => NotificationRecord.from(row as Map))
        .toList(growable: false);
  }

  @override
  Future<int> unreadCount() async {
    final data = await _client.rpc('get_effective_notification_unread_count');
    return _parseCount(data, 'Unexpected notification count response.');
  }

  @override
  Future<bool> markRead(String notificationId) async {
    final data = await _client.rpc(
      'mark_effective_notification_read',
      params: {'p_notification_id': notificationId},
    );
    return data == true;
  }

  @override
  Future<int> markAllRead() async {
    final data = await _client.rpc('mark_all_effective_notifications_read');
    return _parseCount(data, 'Unexpected notification mutation response.');
  }

  @override
  Future<int> clearOwn() async {
    final data = await _client.rpc('clear_effective_notifications');
    return _parseCount(data, 'Unexpected notification mutation response.');
  }

  int _parseCount(dynamic data, String message) {
    final count = data is num ? data.toInt() : int.tryParse(data.toString());
    if (count == null) throw FormatException(message);
    return count < 0 ? 0 : count;
  }
}
