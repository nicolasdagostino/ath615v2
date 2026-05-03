import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';

import '../../../../core/widgets/app_card.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final rows = await _client
          .from('notifications')
          .select(
            'id, title, body, type, data, scheduled_for, sent_at, read_at',
          )
          .eq('user_id', user.id)
          .order('scheduled_for', ascending: false)
          .limit(50);

      if (!mounted) return;
      setState(() {
        _notifications = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.notificationsLoadError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return '';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;

    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    if (notification['read_at'] != null) return;

    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notification['id']);

      if (!mounted) return;
      setState(() {
        notification['read_at'] = DateTime.now().toUtc().toIso8601String();
      });
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', user.id)
          .isFilter('read_at', null)
          .not('sent_at', 'is', null);

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.notificationsMarkReadError(e))),
      );
    }
  }

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    await _markAsRead(notification);

    final data = notification['data'];

    if (data is Map && data['workoutId'] != null) {
      if (!mounted) return;
      context.push('/workout/${data['workoutId']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appStrings.notificationsTitle),
        actions: [
          IconButton(
            tooltip: appStrings.notificationsMarkRead,
            onPressed: _markAllAsRead,
            icon: const Icon(Icons.done_all),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? Center(child: Text(appStrings.notificationsEmpty))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                final sentAt = notification['sent_at']?.toString();
                final readAt = notification['read_at']?.toString();
                final isSent = sentAt != null && sentAt.isNotEmpty;
                final isUnread = isSent && (readAt == null || readAt.isEmpty);

                return AppCard(
                  padding: EdgeInsets.zero,
                  onTap: () => _openNotification(notification),
                  child: ListTile(
                    leading: Icon(
                      isUnread
                          ? Icons.notifications_active
                          : isSent
                          ? Icons.notifications_none
                          : Icons.schedule,
                    ),
                    title: Text(
                      notification['title']?.toString() ??
                          appStrings.notificationFallbackTitle,
                      style: TextStyle(
                        fontWeight: isUnread
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((notification['body']?.toString() ?? '').isNotEmpty)
                          Text(notification['body'].toString()),
                        const SizedBox(height: 4),
                        Text(
                          isSent
                              ? appStrings.notificationSent(_formatDate(sentAt))
                              : appStrings.notificationScheduled(
                                  _formatDate(
                                    notification['scheduled_for']?.toString(),
                                  ),
                                ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
    );
  }
}
