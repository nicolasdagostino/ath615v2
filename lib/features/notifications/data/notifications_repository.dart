import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotificationRecord = Map<String, dynamic>;

class CommunicationReactionSummary {
  const CommunicationReactionSummary({
    required this.thumbsUpCount,
    required this.heartCount,
    required this.myReaction,
  });

  final int thumbsUpCount;
  final int heartCount;
  final String? myReaction;

  factory CommunicationReactionSummary.fromRpc(dynamic data) {
    final rows = data is List ? data : const [];
    final row = rows.isNotEmpty
        ? Map<String, dynamic>.from(rows.first as Map)
        : const <String, dynamic>{};
    return CommunicationReactionSummary(
      thumbsUpCount: (row['thumbs_up_count'] as num?)?.toInt() ?? 0,
      heartCount: (row['heart_count'] as num?)?.toInt() ?? 0,
      myReaction: row['my_reaction']?.toString(),
    );
  }
}

class NotificationsInboxEvents extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final notificationsInboxEvents = NotificationsInboxEvents();

abstract interface class NotificationsRepository {
  Future<List<NotificationRecord>> listOwn();
  Future<int> unreadCount();
  Future<bool> markRead(String notificationId);
  Future<int> markAllRead();
  Future<int> clearCategory(String category);
  Future<CommunicationReactionSummary> loadCommunicationReactions(
    String notificationId,
  );
  Future<CommunicationReactionSummary> setCommunicationReaction(
    String notificationId,
    String? reaction,
  );
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
  Future<int> clearCategory(String category) async {
    final data = await _client.rpc(
      'clear_effective_notifications_by_category',
      params: {'p_category': category},
    );
    return _parseCount(data, 'Unexpected notification mutation response.');
  }

  @override
  Future<CommunicationReactionSummary> loadCommunicationReactions(
    String notificationId,
  ) async => CommunicationReactionSummary.fromRpc(
    await _client.rpc(
      'get_communication_reactions',
      params: {'p_notification_id': notificationId},
    ),
  );

  @override
  Future<CommunicationReactionSummary> setCommunicationReaction(
    String notificationId,
    String? reaction,
  ) async => CommunicationReactionSummary.fromRpc(
    await _client.rpc(
      'set_communication_reaction',
      params: {'p_notification_id': notificationId, 'p_reaction': reaction},
    ),
  );

  int _parseCount(dynamic data, String message) {
    final count = data is num ? data.toInt() : int.tryParse(data.toString());
    if (count == null) throw FormatException(message);
    return count < 0 ? 0 : count;
  }
}
