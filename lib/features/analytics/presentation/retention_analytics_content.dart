import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_async_state.dart';
import '../../../core/widgets/app_form_visuals.dart';
import '../../../core/widgets/app_large_form_sheet.dart';
import '../data/analytics_repository.dart';
import '../domain/analytics_models.dart';

class AnalyticsRetentionContent extends StatefulWidget {
  const AnalyticsRetentionContent({
    super.key,
    required this.summary,
    required this.repository,
    this.onOpenMember,
  });

  final RetentionSummary summary;
  final AnalyticsRepository repository;
  final ValueChanged<Map<String, dynamic>>? onOpenMember;

  @override
  State<AnalyticsRetentionContent> createState() =>
      _AnalyticsRetentionContentState();
}

class _AnalyticsRetentionContentState extends State<AnalyticsRetentionContent> {
  static const _pageSize = 20;
  RetentionSegment? _segment;
  final List<RetentionMember> _members = [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  int _totalCount = 0;
  bool _hasMore = false;

  Future<void> _openSegment(RetentionSegment segment) async {
    setState(() {
      _segment = segment;
      _members.clear();
      _selected.clear();
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.loadRetentionSegment(
        segment,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted || _segment != segment) return;
      setState(() {
        _members.addAll(page.items);
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final segment = _segment;
    if (segment == null || !_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repository.loadRetentionSegment(
        segment,
        limit: _pageSize,
        offset: _members.length,
      );
      if (!mounted || _segment != segment) return;
      setState(() {
        _members.addAll(page.items);
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appStrings.analyticsRetentionLoadError)),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toggle(String userId) => setState(() {
    if (!_selected.add(userId)) _selected.remove(userId);
  });

  void _selectVisible() => setState(() {
    _selected.addAll(_members.map((member) => member.userId));
  });

  Future<void> _compose() async {
    final recipients = _members
        .where((member) => _selected.contains(member.userId))
        .toList();
    if (recipients.isEmpty) return;
    final sent = await showAppLargeFormSheet<bool>(
      context: context,
      builder: (_) => _RetentionCommunicationSheet(
        repository: widget.repository,
        recipients: recipients,
      ),
    );
    if (sent == true && mounted) {
      setState(_selected.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appStrings.retentionCommunicationSent(recipients.length),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final segment = _segment;
    if (segment == null) return _summary(context);
    return _segmentList(context, segment);
  }

  Widget _summary(BuildContext context) => Column(
    key: const ValueKey('analytics-retention-overview'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        appStrings.analyticsRetentionIntro,
        style: AppTypography.bodySecondary(context),
      ),
      const SizedBox(height: AppSpacing.md),
      ...RetentionSegment.values.map(
        (segment) => _RetentionSegmentRow(
          segment: segment,
          count: widget.summary.countFor(segment),
          onTap: () => _openSegment(segment),
        ),
      ),
    ],
  );

  Widget _segmentList(BuildContext context, RetentionSegment segment) => Column(
    key: const ValueKey('analytics-retention-segment'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: () => setState(() {
          _segment = null;
          _members.clear();
          _selected.clear();
        }),
        icon: const Icon(Icons.arrow_back_rounded),
        label: Text(appStrings.analyticsRetentionBack),
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      Text(
        _segmentLabel(segment).toUpperCase(),
        style: AppTypography.sectionTitle(context),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        appStrings.retentionMembersCount(_totalCount),
        style: AppTypography.bodySecondary(context),
      ),
      const SizedBox(height: AppSpacing.sm),
      if (_members.isNotEmpty)
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: _selectVisible,
              child: Text(appStrings.retentionSelectVisible),
            ),
            if (_selected.isNotEmpty)
              TextButton(
                onPressed: () => setState(_selected.clear),
                child: Text(appStrings.retentionClearSelection),
              ),
            Text(
              appStrings.retentionSelectedCount(_selected.length),
              style: AppTypography.helper(context),
            ),
          ],
        ),
      if (_loading)
        AppAsyncState.loading(message: appStrings.analyticsLoading)
      else if (_error != null)
        AppAsyncState.error(
          message: appStrings.analyticsRetentionLoadError,
          actionLabel: appStrings.retry,
          onAction: () => _openSegment(segment),
        )
      else if (_members.isEmpty)
        AppAsyncState.empty(
          message: _emptyLabel(segment),
          icon: Icons.people_outline_rounded,
        )
      else ...[
        ..._members.map(
          (member) => _RetentionMemberRow(
            member: member,
            segment: segment,
            selected: _selected.contains(member.userId),
            onToggle: () => _toggle(member.userId),
            onOpen: widget.onOpenMember == null
                ? null
                : () => widget.onOpenMember!(member.memberDetailData),
          ),
        ),
        if (_hasMore)
          Center(
            child: TextButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: Text(
                _loadingMore
                    ? appStrings.analyticsLoading
                    : appStrings.analyticsRetentionLoadMore,
              ),
            ),
          ),
      ],
      if (_selected.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        AppFormSubmitButton(
          key: const ValueKey('retention-send-communication'),
          label: appStrings.sendCommunication,
          loading: false,
          enabled: true,
          onPressed: _compose,
          accentColor: AppColors.primary,
          icon: Icons.campaign_outlined,
        ),
      ],
    ],
  );
}

class _RetentionSegmentRow extends StatelessWidget {
  const _RetentionSegmentRow({
    required this.segment,
    required this.count,
    required this.onTap,
  });
  final RetentionSegment segment;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadii.card),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _segmentLabel(segment),
              style: AppTypography.body(context),
            ),
          ),
          Text(
            appStrings.retentionMembersCount(count),
            style: AppTypography.helper(
              context,
            ).copyWith(color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary(context),
          ),
        ],
      ),
    ),
  );
}

class _RetentionMemberRow extends StatelessWidget {
  const _RetentionMemberRow({
    required this.member,
    required this.segment,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
  });
  final RetentionMember member;
  final RetentionSegment segment;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border(context))),
    ),
    child: Row(
      children: [
        Checkbox(
          value: selected,
          onChanged: (_) => onToggle(),
          activeColor: AppColors.primary,
        ),
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            backgroundImage: member.avatarUrl == null
                ? null
                : NetworkImage(member.avatarUrl!),
            child: member.avatarUrl == null
                ? Text(
                    member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
                    style: AppTypography.body(
                      context,
                    ).copyWith(color: AppColors.primary),
                  )
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: AppTypography.body(context)),
                Text(
                  _memberContext(member, segment),
                  style: AppTypography.helper(context),
                ),
                if (member.hasFutureBooking && member.futureBookingAt != null)
                  Text(
                    appStrings.retentionFutureBooking(
                      DateFormat.MMMd(
                        appStrings.isEs ? 'es' : 'en',
                      ).add_Hm().format(member.futureBookingAt!.toLocal()),
                    ),
                    style: AppTypography.helper(
                      context,
                    ).copyWith(color: AppColors.primary),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _RetentionCommunicationSheet extends StatefulWidget {
  const _RetentionCommunicationSheet({
    required this.repository,
    required this.recipients,
  });
  final AnalyticsRepository repository;
  final List<RetentionMember> recipients;

  @override
  State<_RetentionCommunicationSheet> createState() =>
      _RetentionCommunicationSheetState();
}

class _RetentionCommunicationSheetState
    extends State<_RetentionCommunicationSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.retentionCommunicationRequired)),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appStrings.retentionConfirmTitle),
        content: Text(
          appStrings.retentionConfirmMessage(widget.recipients.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(appStrings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(appStrings.sendCommunication),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sending = true);
    try {
      await widget.repository.sendRetentionCommunication(
        recipientIds: widget.recipients.map((member) => member.userId).toList(),
        title: title,
        body: body,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appStrings.retentionCommunicationError)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AppFormHeader(
        title: appStrings.sendCommunication,
        onClose: Navigator.of(context).pop,
        accentColor: AppColors.primary,
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenX),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            AppFormSectionLabel(
              label: appStrings.retentionRecipients.toUpperCase(),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.recipients.map((member) => member.name).join(', '),
              style: AppTypography.body(context),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('retention-communication-title'),
              controller: _title,
              maxLength: 120,
              style: appFormValueStyle(context),
              decoration: appFormInput(
                context,
                icon: Icons.title_rounded,
                hintText: appStrings.notificationTitleLabel,
                accentColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('retention-communication-body'),
              controller: _body,
              minLines: 5,
              maxLines: 9,
              maxLength: 2000,
              style: appFormValueStyle(context),
              decoration: appFormInput(
                context,
                icon: Icons.notes_rounded,
                hintText: appStrings.notificationMessageLabel,
                accentColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.sm,
          AppSpacing.screenX,
          AppSpacing.md,
        ),
        child: AppFormSubmitButton(
          label: appStrings.sendCommunication,
          loading: _sending,
          enabled: !_sending,
          onPressed: _send,
          accentColor: AppColors.primary,
          icon: Icons.send_outlined,
        ),
      ),
    ],
  );
}

String _segmentLabel(RetentionSegment segment) => switch (segment) {
  RetentionSegment.noAttendance7 => appStrings.retentionNoAttendance7,
  RetentionSegment.noAttendance14 => appStrings.retentionNoAttendance14,
  RetentionSegment.noAttendance30 => appStrings.retentionNoAttendance30,
  RetentionSegment.activeMembershipNoRecentUse =>
    appStrings.retentionActivePlanNoUse,
  RetentionSegment.noUsableMembership => appStrings.retentionNoActivePlan,
  RetentionSegment.expiringSoon => appStrings.retentionExpiringSoon,
  RetentionSegment.lowCredits => appStrings.retentionLowCredits,
  RetentionSegment.firstClassNoReturn => appStrings.retentionFirstClassNoReturn,
  RetentionSegment.inactiveRecent => appStrings.retentionInactiveRecent,
  RetentionSegment.repeatedNoShows => appStrings.retentionRepeatedNoShows,
};

String _emptyLabel(RetentionSegment segment) => switch (segment) {
  RetentionSegment.expiringSoon => appStrings.retentionNoExpiring,
  RetentionSegment.noAttendance7 ||
  RetentionSegment.noAttendance14 ||
  RetentionSegment.noAttendance30 ||
  RetentionSegment.inactiveRecent => appStrings.retentionEveryoneRecent,
  _ => appStrings.retentionNoMembers,
};

String _memberContext(RetentionMember member, RetentionSegment segment) {
  if (segment == RetentionSegment.lowCredits) {
    return appStrings.creditsRemainingLabel(member.creditsRemaining ?? 0);
  }
  if (segment == RetentionSegment.expiringSoon &&
      member.membershipEndsAt != null) {
    final days = DateUtils.dateOnly(
      member.membershipEndsAt!.toLocal(),
    ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
    return appStrings.retentionExpiresIn(days);
  }
  if (segment == RetentionSegment.repeatedNoShows) {
    return appStrings.retentionNoShows30(member.noShowCount30d);
  }
  if (member.lastAttendedAt == null) return appStrings.retentionNoAttendanceYet;
  final days = DateUtils.dateOnly(
    DateTime.now(),
  ).difference(DateUtils.dateOnly(member.lastAttendedAt!.toLocal())).inDays;
  if (segment == RetentionSegment.firstClassNoReturn) {
    return appStrings.retentionFirstClassDaysAgo(days);
  }
  return appStrings.retentionLastAttendanceDaysAgo(days);
}
