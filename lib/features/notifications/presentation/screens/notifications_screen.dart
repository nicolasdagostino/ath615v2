import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_async_state.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_message_detail_sheet.dart';
import '../../../../core/widgets/app_primary_gym_header.dart';
import '../../../../core/widgets/app_section_chip.dart';
import '../../data/notifications_repository.dart';
import '../../navigation/notification_destination.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.initialNotificationId,
    this.repository,
    this.gymName,
    this.onNotificationsRead,
    this.onOpenMembershipRequests,
    this.workoutDateResolver,
    this.onOpenWorkoutDate,
  });

  final String? initialNotificationId;
  final NotificationsRepository? repository;
  final String? gymName;
  final VoidCallback? onNotificationsRead;
  final VoidCallback? onOpenMembershipRequests;
  final Future<DateTime?> Function(Map<String, dynamic> data)?
  workoutDateResolver;
  final ValueChanged<DateTime>? onOpenWorkoutDate;

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
    final clearsCommunications = _section == _MessagesSection.communications;
    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: clearsCommunications
          ? appStrings.communicationsClearTitle
          : appStrings.personalNotificationsClearTitle,
      message: clearsCommunications
          ? appStrings.communicationsClearMessage
          : appStrings.personalNotificationsClearMessage,
      confirmLabel: appStrings.clear,
      cancelLabel: appStrings.cancel,
      icon: Icons.delete_sweep_outlined,
    );
    if (!confirmed) return;

    try {
      await _repository.clearCategory(
        clearsCommunications ? 'communication' : 'notification',
      );
      if (!mounted) return;
      setState(
        () => _notifications.removeWhere(
          (notification) =>
              (notification['type']?.toString() == 'communication') ==
              clearsCommunications,
        ),
      );
      notificationsInboxEvents.refresh();
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

    final normalizedData = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    if (isWorkoutNotification(
      type: notification['type'],
      data: normalizedData,
    )) {
      final date =
          await (widget.workoutDateResolver?.call(normalizedData) ??
              resolveWorkoutNotificationDate(
                client: Supabase.instance.client,
                data: normalizedData,
              ));
      if (!mounted) return;
      final destinationDate = date ?? DateTime.now();
      if (widget.onOpenWorkoutDate case final callback?) {
        callback(destinationDate);
      } else {
        context.go(wodDestination(destinationDate));
      }
      return;
    }

    if (!mounted) return;
    await showAppMessageDetailSheet(
      context: context,
      title:
          notification['title']?.toString() ??
          appStrings.notificationFallbackTitle,
      body: notification['body']?.toString() ?? '',
      metadata: notification['sent_at'] != null
          ? appStrings.notificationSent(
              _formatDate(notification['sent_at']?.toString()),
            )
          : appStrings.notificationScheduled(
              _formatDate(notification['scheduled_for']?.toString()),
            ),
      icon: _notificationIcon(notification['type']?.toString()),
      closeLabel: appStrings.close,
      footer: notification['type']?.toString() == 'communication'
          ? _CommunicationReactionBar(
              notificationId: notification['id'].toString(),
              repository: _repository,
            )
          : null,
    );
  }

  IconData _notificationIcon(String? type) => switch (type) {
    'communication' => Icons.campaign_outlined,
    'class_reminder' => Icons.calendar_month_outlined,
    'birthday' => Icons.cake_outlined,
    'waitlist_promoted' => Icons.group_add_outlined,
    'gym_join_approved' || 'gym_join_rejected' => Icons.storefront_outlined,
    'membership_approved' ||
    'membership_scheduled' ||
    'membership_payment_completed' => Icons.card_membership_outlined,
    _ => Icons.notifications_none_rounded,
  };

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
              color: AppColors.primary,
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

class _CommunicationReactionBar extends StatefulWidget {
  const _CommunicationReactionBar({
    required this.notificationId,
    required this.repository,
  });

  final String notificationId;
  final NotificationsRepository repository;

  @override
  State<_CommunicationReactionBar> createState() =>
      _CommunicationReactionBarState();
}

class _CommunicationReactionBarState extends State<_CommunicationReactionBar> {
  CommunicationReactionSummary? _summary;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final summary = await widget.repository.loadCommunicationReactions(
        widget.notificationId,
      );
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      // The communication remains readable if reaction metadata cannot load.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String reaction) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final summary = await widget.repository.setCommunicationReaction(
        widget.notificationId,
        reaction,
      );
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      // Keep the last confirmed state when the mutation fails.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();

    return Wrap(
      key: const ValueKey('communication-reactions'),
      spacing: AppSpacing.sm,
      children: [
        _ReactionButton(
          key: const ValueKey('reaction-thumbs-up'),
          emoji: '👍',
          count: summary.thumbsUpCount,
          selected: summary.myReaction == 'thumbs_up',
          enabled: !_saving,
          onTap: () => _toggle('thumbs_up'),
        ),
        _ReactionButton(
          key: const ValueKey('reaction-heart'),
          emoji: '❤️',
          count: summary.heartCount,
          selected: summary.myReaction == 'heart',
          enabled: !_saving,
          onTap: () => _toggle('heart'),
        ),
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    super.key,
    required this.emoji,
    required this.count,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? AppColors.primary.withValues(alpha: 0.12)
        : AppColors.surfaceAlt(context),
    shape: StadiumBorder(
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.border(context),
      ),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          '$emoji $count',
          style: AppTypography.body(context).copyWith(
            color: selected
                ? AppColors.primary
                : AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

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
