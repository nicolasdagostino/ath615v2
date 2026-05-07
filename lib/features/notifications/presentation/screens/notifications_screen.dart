import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';

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
          .select('id, title, body, type, data, scheduled_for, sent_at, read_at')
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

  Future<void> _clearNotifications() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text('CLEAR NOTIFICATIONS?', style: _NotificationText.title),
                  const SizedBox(height: 10),
                  Text(
                    'This will remove all notifications from your list.',
                    style: _NotificationText.body,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF384152),
                            side: const BorderSide(color: Color(0xFFE1E4EA)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text('CANCEL', style: _NotificationText.button),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFB42318),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'CLEAR',
                            style: _NotificationText.button.copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    final user = _client.auth.currentUser;
    if (user == null) return;

    if (!mounted) return;

    final previous = List<Map<String, dynamic>>.from(_notifications);
    setState(() => _notifications = []);

    try {
      await _client.from('notifications').delete().eq('user_id', user.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notifications = previous);
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

  int get _unreadCount {
    return _notifications.where((n) {
      final sentAt = n['sent_at']?.toString();
      final readAt = n['read_at']?.toString();
      return sentAt != null && sentAt.isNotEmpty && (readAt == null || readAt.isEmpty);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Column(
          children: [
            _NotificationsHeader(
              unreadCount: _unreadCount,
              onBack: () => Navigator.of(context).pop(),
              onMarkAllRead: _markAllAsRead,
              onClear: _clearNotifications,
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFB59B6A),
                onRefresh: _clearNotifications,
                child: _loading
                    ? const _NotificationsLoadingState()
                    : _notifications.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(28, 120, 28, 24),
                            children: [
                              _NotificationsEmptyState(
                                message: appStrings.notificationsEmpty,
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                            itemCount: _notifications.length,
                            itemBuilder: (context, index) {
                              final notification = _notifications[index];
                              final sentAt = notification['sent_at']?.toString();
                              final readAt = notification['read_at']?.toString();
                              final isSent = sentAt != null && sentAt.isNotEmpty;
                              final isUnread =
                                  isSent && (readAt == null || readAt.isEmpty);

                              return _NotificationCard(
                                title: notification['title']?.toString() ??
                                    appStrings.notificationFallbackTitle,
                                body: notification['body']?.toString() ?? '',
                                meta: isSent
                                    ? appStrings.notificationSent(_formatDate(sentAt))
                                    : appStrings.notificationScheduled(
                                        _formatDate(
                                          notification['scheduled_for']?.toString(),
                                        ),
                                      ),
                                isUnread: isUnread,
                                isSent: isSent,
                                onTap: () => _openNotification(notification),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({
    required this.unreadCount,
    required this.onBack,
    required this.onMarkAllRead,
    required this.onClear,
  });

  final int unreadCount;
  final VoidCallback onBack;
  final VoidCallback onMarkAllRead;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: SizedBox(
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _HeaderIcon(
                  icon: Icons.chevron_left_rounded,
                  onTap: onBack,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('NOTIFICATIONS', style: _NotificationText.title),
                  const SizedBox(height: 2),
                  Text(
                    unreadCount == 0 ? 'All caught up' : '$unreadCount unread',
                    style: _NotificationText.subtle,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                children: [
                  _HeaderIcon(
                    icon: Icons.done_all_rounded,
                    onTap: onMarkAllRead,
                  ),
                  const SizedBox(width: 8),
                  _HeaderIcon(
                    icon: Icons.delete_sweep_outlined,
                    onTap: onClear,
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

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3EA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: const Color(0xFFB59B6A)),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.title,
    required this.body,
    required this.meta,
    required this.isUnread,
    required this.isSent,
    required this.onTap,
  });

  final String title;
  final String body;
  final String meta;
  final bool isUnread;
  final bool isSent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = isUnread
        ? Icons.notifications_active_outlined
        : isSent
            ? Icons.notifications_none_rounded
            : Icons.schedule_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isUnread
                        ? const Color(0xFFF7F3EA)
                        : const Color(0xFFF4F5F7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: isUnread
                        ? const Color(0xFFB59B6A)
                        : const Color(0xFF8F96A3),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: _NotificationText.cardTitle),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(body, style: _NotificationText.body),
                      ],
                      const SizedBox(height: 8),
                      Text(meta, style: _NotificationText.subtle),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8F96A3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('NO NOTIFICATIONS', textAlign: TextAlign.center, style: _NotificationText.emptyTitle),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center, style: _NotificationText.subtle),
      ],
    );
  }
}

class _NotificationsLoadingState extends StatelessWidget {
  const _NotificationsLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      children: const [
        _NotificationSkeletonCard(),
        _NotificationSkeletonCard(),
        _NotificationSkeletonCard(),
      ],
    );
  }
}

class _NotificationSkeletonCard extends StatelessWidget {
  const _NotificationSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          const _SkeletonBox(width: 42, height: 42, radius: 14),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonBox(width: 180, height: 18, radius: 999),
                SizedBox(height: 10),
                _SkeletonBox(width: double.infinity, height: 14, radius: 999),
                SizedBox(height: 8),
                _SkeletonBox(width: 130, height: 12, radius: 999),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF0),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _NotificationText {
  const _NotificationText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle cardTitle = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.2,
    height: 1.05,
  );

  static TextStyle emptyTitle = GoogleFonts.barlowCondensed(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle button = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
    letterSpacing: 0.3,
    height: 1,
  );
}
