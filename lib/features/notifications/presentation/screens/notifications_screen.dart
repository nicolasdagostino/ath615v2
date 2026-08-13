import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_async_state.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_primary_gym_header.dart';
import '../../../../core/widgets/app_section_chip.dart';
import '../../data/notifications_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.initialNotificationId,
    this.repository,
    this.gymName,
    this.onNotificationsRead,
    this.onOpenMembershipRequests,
  });

  final String? initialNotificationId;
  final NotificationsRepository? repository;
  final String? gymName;
  final VoidCallback? onNotificationsRead;
  final VoidCallback? onOpenMembershipRequests;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _handledInitialNotification = false;
  List<Map<String, dynamic>> _notifications = [];
  _MessagesSection _section = _MessagesSection.communications;

  late final NotificationsRepository _repository =
      widget.repository ??
      SupabaseNotificationsRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final rows = await _repository.listOwn();

      if (!mounted) return;
      setState(() {
        _notifications = List<Map<String, dynamic>>.from(rows);
      });

      widget.onNotificationsRead?.call();
      _openInitialNotificationIfNeeded();
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
      final notificationId = notification['id']?.toString();
      if (notificationId == null || notificationId.isEmpty) return;
      final updated = await _repository.markRead(notificationId);
      if (!updated) return;

      if (!mounted) return;
      setState(() {
        notification['read_at'] = DateTime.now().toUtc().toIso8601String();
      });
      widget.onNotificationsRead?.call();
    } catch (_) {}
  }

  Future<void> _clearNotifications() async {
    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: appStrings.notificationsClearTitle,
      message: appStrings.notificationsClearMessage,
      confirmLabel: appStrings.clear,
      cancelLabel: appStrings.cancel,
      icon: Icons.delete_sweep_outlined,
    );
    if (!confirmed) return;

    try {
      await _repository.clearOwn();
      if (!mounted) return;
      setState(_notifications.clear);
      widget.onNotificationsRead?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.notificationsMarkReadError(error))),
      );
    }
  }

  void _openInitialNotificationIfNeeded() {
    if (_handledInitialNotification) return;

    final notificationId = widget.initialNotificationId?.trim();
    if (notificationId == null || notificationId.isEmpty) return;

    final index = _notifications.indexWhere(
      (notification) => notification['id']?.toString() == notificationId,
    );

    if (index == -1) return;

    _handledInitialNotification = true;
    final notification = _notifications[index];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openNotification(notification);
    });
  }

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    await _markAsRead(notification);

    final data = notification['data'];

    if (notification['type']?.toString() == 'membership_request') {
      final callback = widget.onOpenMembershipRequests;
      if (callback != null) {
        callback();
      } else if (mounted) {
        context.go('/app?section=membership');
      }
      return;
    }

    if (data is Map && data['workoutId'] != null) {
      if (!mounted) return;
      context.push('/workout/${data['workoutId']}');
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationDetailsSheet(
        title:
            notification['title']?.toString() ??
            appStrings.notificationFallbackTitle,
        body: notification['body']?.toString() ?? '',
        meta: notification['sent_at'] != null
            ? appStrings.notificationSent(
                _formatDate(notification['sent_at']?.toString()),
              )
            : appStrings.notificationScheduled(
                _formatDate(notification['scheduled_for']?.toString()),
              ),
      ),
    );
  }

  List<Map<String, dynamic>> get _visibleNotifications => _notifications
      .where(
        (notification) =>
            (notification['type']?.toString() == 'communication') ==
            (_section == _MessagesSection.communications),
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          AppPrimaryGymHeader(gymName: widget.gymName),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenX,
              AppSpacing.md,
              AppSpacing.screenX,
              0,
            ),
            child: Row(
              key: const ValueKey('messages-section-chips'),
              children: [
                Expanded(
                  child: AppSectionChip(
                    label: appStrings.communications,
                    selected: _section == _MessagesSection.communications,
                    onTap: () => setState(
                      () => _section = _MessagesSection.communications,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppSectionChip(
                    label: appStrings.personalNotifications,
                    selected: _section == _MessagesSection.notifications,
                    onTap: () => setState(
                      () => _section = _MessagesSection.notifications,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_notifications.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.screenX,
                  right: AppSpacing.screenX,
                  top: AppSpacing.xs,
                ),
                child: TextButton.icon(
                  key: const ValueKey('messages-clear-action'),
                  onPressed: _clearNotifications,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: Text(appStrings.clear.toUpperCase()),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    textStyle: AppTypography.buttonLabel(context),
                    minimumSize: const Size(
                      AppSizes.minimumTouchTarget,
                      AppSizes.minimumTouchTarget,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accent,
              onRefresh: _load,
              child: _loading
                  ? const _NotificationsLoadingState()
                  : _visibleNotifications.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(28, 120, 28, 24),
                      children: [
                        AppAsyncState.empty(
                          message: _section == _MessagesSection.communications
                              ? appStrings.communicationsEmpty
                              : appStrings.personalNotificationsEmpty,
                          icon: _section == _MessagesSection.communications
                              ? Icons.campaign_outlined
                              : Icons.notifications_none_rounded,
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                      itemCount: _visibleNotifications.length,
                      itemBuilder: (context, index) {
                        final notification = _visibleNotifications[index];
                        final sentAt = notification['sent_at']?.toString();
                        final readAt = notification['read_at']?.toString();
                        final isSent = sentAt != null && sentAt.isNotEmpty;
                        final isUnread =
                            isSent && (readAt == null || readAt.isEmpty);

                        return _MessageRow(
                          title:
                              notification['title']?.toString() ??
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
    );
  }
}

enum _MessagesSection { communications, notifications }

class _MessageRow extends StatelessWidget {
  const _MessageRow({
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
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border(context), width: 0.8),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSent ? Icons.campaign_outlined : Icons.schedule_outlined,
              color: isUnread ? AppColors.primary : AppColors.muted(context),
              size: 22,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.itemTitle(context)),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySecondary(context),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(meta, style: AppTypography.helper(context)),
                ],
              ),
            ),
            if (isUnread)
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NotificationDetailsSheet extends StatelessWidget {
  const _NotificationDetailsSheet({
    required this.title,
    required this.body,
    required this.meta,
  });

  final String title;
  final String body;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt(context),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.campaign_outlined,
                      color: AppColors.accent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: _NotificationText.title(
                        context,
                      ).copyWith(fontSize: 24),
                    ),
                  ),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  body,
                  style: _NotificationText.body(context).copyWith(
                    color: AppColors.textPrimary(context),
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(meta, style: _NotificationText.subtle(context)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary(context),
                    side: BorderSide(color: AppColors.border(context)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    appStrings.close.toUpperCase(),
                    style: _NotificationText.button(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
        color: AppColors.surface(context),
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
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _NotificationText {
  const _NotificationText._();

  static TextStyle title(BuildContext context) => GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary(context),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle body(BuildContext context) => GoogleFonts.barlowCondensed(
    color: AppColors.textSecondary(context),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle button(BuildContext context) => GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary(context),
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle subtle(BuildContext context) => GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary(context),
    letterSpacing: 0.3,
    height: 1,
  );
}
