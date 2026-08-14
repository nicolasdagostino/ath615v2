import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';

const int membershipHistoryPageSize = 15;
const int membershipUsagePageSize = 15;

abstract class UserMembershipsDataSource {
  Future<List<Map<String, dynamic>>> loadCurrentAndScheduled();

  Future<List<Map<String, dynamic>>> loadPendingRequests();

  Future<List<Map<String, dynamic>>> loadHistory({
    required int offset,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> loadUsage({
    required String membershipId,
    required int offset,
    required int limit,
  });
}

bool isFinalMembershipUsage(
  Map<String, dynamic> booking,
  String membershipId,
) =>
    booking['membership_id']?.toString() == membershipId &&
    booking['status']?.toString() != 'cancelled';

class SupabaseUserMembershipsDataSource implements UserMembershipsDataSource {
  SupabaseUserMembershipsDataSource(this.client, {String? userId})
    : _requestedUserId = userId;

  final SupabaseClient client;
  final String? _requestedUserId;

  String? get _userId => _requestedUserId ?? client.auth.currentUser?.id;

  static const _membershipSelect =
      'id, credits_remaining, starts_at, expires_at, ends_at, status, '
      'is_active, created_at, membership_plans(name, plan_type, credits)';

  @override
  Future<List<Map<String, dynamic>>> loadCurrentAndScheduled() async {
    final userId = _userId;
    if (userId == null) return const [];
    final rows = await client
        .from('member_memberships')
        .select(_membershipSelect)
        .eq('user_id', userId)
        .inFilter('status', const ['active', 'scheduled'])
        .order('starts_at')
        .limit(20);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> loadPendingRequests() async {
    final userId = _userId;
    if (userId == null) return const [];
    final rows = await client
        .from('membership_requests')
        .select(
          'id, status, payment_status, created_at, '
          'membership_plans(name, plan_type, credits, price, currency)',
        )
        .eq('user_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> loadHistory({
    required int offset,
    required int limit,
  }) async {
    final userId = _userId;
    if (userId == null) return const [];
    final rows = await client
        .from('member_memberships')
        .select(_membershipSelect)
        .eq('user_id', userId)
        .inFilter('status', const [
          'exhausted',
          'expired',
          'cancelled',
          'replaced',
        ])
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> loadUsage({
    required String membershipId,
    required int offset,
    required int limit,
  }) async {
    final rows = await client
        .from('class_bookings')
        .select(
          'id, membership_id, status, created_at, '
          'classes(title, starts_at, programs(name))',
        )
        .eq('membership_id', membershipId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(
      rows,
    ).where((row) => isFinalMembershipUsage(row, membershipId)).toList();
  }
}

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key, this.dataSource});

  @visibleForTesting
  final UserMembershipsDataSource? dataSource;

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  late final UserMembershipsDataSource _source;
  final List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _active = const [];
  List<Map<String, dynamic>> _scheduled = const [];
  List<Map<String, dynamic>> _pending = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _source =
        widget.dataSource ??
        SupabaseUserMembershipsDataSource(Supabase.instance.client);
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final results = await Future.wait([
      _source.loadCurrentAndScheduled(),
      _source.loadPendingRequests(),
      _source.loadHistory(offset: 0, limit: membershipHistoryPageSize),
    ]);
    if (!mounted) return;
    final current = results[0];
    final pending = results[1];
    final history = results[2];
    setState(() {
      _active = current.where((row) => row['status'] == 'active').toList();
      _scheduled = current
          .where((row) => row['status'] == 'scheduled')
          .toList();
      _pending = pending;
      _history
        ..clear()
        ..addAll(history);
      _hasMore = history.length == membershipHistoryPageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = await _source.loadHistory(
      offset: _history.length,
      limit: membershipHistoryPageSize,
    );
    if (!mounted) return;
    setState(() {
      _history.addAll(next);
      _hasMore = next.length == membershipHistoryPageSize;
      _loadingMore = false;
    });
  }

  Future<void> _openDetail(Map<String, dynamic> membership) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => FractionallySizedBox(
          heightFactor: .92,
          child: MembershipDetailSheet(
            membership: membership,
            dataSource: _source,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: SafeArea(
      child: Column(
        children: [
          AppSecondaryActionHeader(
            title: appStrings.myMemberships,
            onBack: context.pop,
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : ListView(
                    key: const ValueKey('memberships-scroll'),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenX,
                      AppSpacing.lg,
                      AppSpacing.screenX,
                      88,
                    ),
                    children: [
                      _SectionTitle(
                        label: appStrings.currentMembership.toUpperCase(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_active.isEmpty)
                        _EmptyMessage(
                          key: const ValueKey('memberships-no-current'),
                          message: appStrings.pick(
                            'You do not have an active membership.',
                            'No tienes una membresía activa.',
                          ),
                        )
                      else
                        ..._active.map(
                          (membership) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _CurrentMembershipCard(
                              membership: membership,
                              onTap: () => _openDetail(membership),
                            ),
                          ),
                        ),
                      if (_scheduled.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _SectionTitle(
                          label: appStrings.pick('UPCOMING', 'PRÓXIMAS'),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        ..._scheduled.map(
                          (membership) => _MembershipRow(
                            membership: membership,
                            onTap: () => _openDetail(membership),
                          ),
                        ),
                      ],
                      if (_pending.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _SectionTitle(
                          label: appStrings.pick('REQUESTED', 'SOLICITADAS'),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        ..._pending.map(
                          (request) => _PendingRequestRow(request: request),
                        ),
                      ],
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _SectionTitle(
                          label: appStrings.pick('HISTORY', 'HISTORIAL'),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        ..._historyWidgets(),
                      ],
                      if (_hasMore) ...[
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton(
                          key: const ValueKey('memberships-load-more'),
                          onPressed: _loadingMore ? null : _loadMore,
                          child: _loadingMore
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                )
                              : Text(appStrings.showMore.toUpperCase()),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      OutlinedButton(
                        key: const ValueKey('memberships-get-subscription'),
                        onPressed: () async {
                          final changed = await context.push<bool>(
                            '/available-memberships/subscription',
                          );
                          if (changed == true) await _loadInitial();
                        },
                        child: Text(appStrings.getSubscription.toUpperCase()),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        key: const ValueKey('memberships-get-dropin'),
                        onPressed: () async {
                          final changed = await context.push<bool>(
                            '/available-memberships/dropin',
                          );
                          if (changed == true) await _loadInitial();
                        },
                        child: Text(appStrings.getDropIn.toUpperCase()),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _historyWidgets() {
    final widgets = <Widget>[];
    int? lastYear;
    for (final membership in _history) {
      final year = membershipDate(membership)?.year ?? 0;
      if (year != lastYear) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: lastYear == null ? AppSpacing.xs : AppSpacing.lg,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              year == 0 ? '—' : '$year',
              key: ValueKey('membership-history-year-$year'),
              style: AppTypography.itemTitle(context),
            ),
          ),
        );
        lastYear = year;
      }
      widgets.add(
        _MembershipRow(
          membership: membership,
          onTap: () => _openDetail(membership),
        ),
      );
    }
    return widgets;
  }
}

Map<String, dynamic> membershipPlan(Map<String, dynamic> membership) {
  final value = membership['membership_plans'];
  return value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
}

DateTime? membershipDate(Map<String, dynamic> membership) => DateTime.tryParse(
  membership['starts_at']?.toString() ??
      membership['created_at']?.toString() ??
      '',
)?.toLocal();

DateTime? membershipEndDate(Map<String, dynamic> membership) =>
    DateTime.tryParse(
      membership['expires_at']?.toString() ??
          membership['ends_at']?.toString() ??
          '',
    )?.toLocal();

String _date(BuildContext context, DateTime? date) {
  if (date == null) return '—';
  return DateFormat(
    'd MMM yyyy',
    Localizations.localeOf(context).languageCode,
  ).format(date);
}

String _planName(Map<String, dynamic> membership) =>
    membershipPlan(membership)['name']?.toString() ?? appStrings.plan;

bool _isUnlimited(Map<String, dynamic> membership) =>
    membershipPlan(membership)['plan_type']?.toString() == 'unlimited' ||
    membership['credits_remaining'] == null;

int? _totalCredits(Map<String, dynamic> membership) =>
    membershipPlan(membership)['credits'] as int?;

int? _remainingCredits(Map<String, dynamic> membership) =>
    membership['credits_remaining'] as int?;

int? _usedCredits(Map<String, dynamic> membership) {
  final total = _totalCredits(membership);
  final remaining = _remainingCredits(membership);
  if (total == null || remaining == null) return null;
  return (total - remaining).clamp(0, total);
}

String _statusLabel(String? status) => switch (status) {
  'active' => appStrings.active,
  'scheduled' => appStrings.scheduled,
  'exhausted' => appStrings.exhausted,
  'expired' => appStrings.expired,
  'cancelled' => appStrings.cancelled,
  'replaced' => appStrings.replaced,
  _ => status ?? '—',
};

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: AppTypography.sectionTitle(context));
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Text(message, style: AppTypography.bodySecondary(context)),
  );
}

class _CurrentMembershipCard extends StatelessWidget {
  const _CurrentMembershipCard({required this.membership, required this.onTap});

  final Map<String, dynamic> membership;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = _totalCredits(membership);
    final remaining = _remainingCredits(membership);
    final used = _usedCredits(membership);
    return Material(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        key: ValueKey('membership-current-${membership['id']}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _planName(membership).toUpperCase(),
                      style: AppTypography.itemTitle(context),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_isUnlimited(membership))
                Text(appStrings.active, style: AppTypography.body(context))
              else ...[
                Text(
                  appStrings.pick(
                    '$used / $total used',
                    '$used / $total utilizadas',
                  ),
                  style: AppTypography.body(context),
                ),
                const SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(
                  value: total == null || total == 0 ? 0 : used! / total,
                  minHeight: 8,
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceAlt(context),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  appStrings.pick(
                    '$remaining credits available',
                    '$remaining créditos disponibles',
                  ),
                  style: AppTypography.bodySecondary(context),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${_date(context, membershipDate(membership))} — '
                '${_date(context, membershipEndDate(membership))}',
                style: AppTypography.bodySecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MembershipRow extends StatelessWidget {
  const _MembershipRow({required this.membership, required this.onTap});
  final Map<String, dynamic> membership;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('membership-row-${membership['id']}'),
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: .7),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _planName(membership).toUpperCase(),
                  style: AppTypography.itemTitle(context),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${_date(context, membershipDate(membership))} — '
                  '${_date(context, membershipEndDate(membership))}',
                  style: AppTypography.bodySecondary(context),
                ),
                if (!_isUnlimited(membership)) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    appStrings.pick(
                      '${_usedCredits(membership)} / '
                          '${_totalCredits(membership)} used',
                      '${_usedCredits(membership)} / '
                          '${_totalCredits(membership)} utilizadas',
                    ),
                    style: AppTypography.helper(context),
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _statusLabel(membership['status']?.toString()),
                    style: AppTypography.helper(context),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary(context),
          ),
        ],
      ),
    ),
  );
}

class _PendingRequestRow extends StatelessWidget {
  const _PendingRequestRow({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('membership-request-${request['id']}'),
    constraints: const BoxConstraints(minHeight: 64),
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: AppColors.border(context), width: .7),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _planName(request).toUpperCase(),
                style: AppTypography.itemTitle(context),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                appStrings.pick('Request pending', 'Solicitud pendiente'),
                style: AppTypography.bodySecondary(context),
              ),
            ],
          ),
        ),
        const Icon(Icons.schedule_rounded, color: AppColors.primary, size: 20),
      ],
    ),
  );
}

class MemberMembershipsSection extends StatefulWidget {
  const MemberMembershipsSection({
    super.key,
    required this.memberId,
    this.dataSource,
    this.includeActive = true,
  });

  final String memberId;
  final UserMembershipsDataSource? dataSource;
  final bool includeActive;

  @override
  State<MemberMembershipsSection> createState() =>
      _MemberMembershipsSectionState();
}

class _MemberMembershipsSectionState extends State<MemberMembershipsSection> {
  late final UserMembershipsDataSource _source =
      widget.dataSource ??
      SupabaseUserMembershipsDataSource(
        Supabase.instance.client,
        userId: widget.memberId,
      );
  final List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _active = const [];
  List<Map<String, dynamic>> _scheduled = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final results = await Future.wait([
      _source.loadCurrentAndScheduled(),
      _source.loadHistory(offset: 0, limit: membershipHistoryPageSize),
    ]);
    if (!mounted) return;
    setState(() {
      _active = results[0].where((row) => row['status'] == 'active').toList();
      _scheduled = results[0]
          .where((row) => row['status'] == 'scheduled')
          .toList();
      _history
        ..clear()
        ..addAll(results[1]);
      _hasMore = results[1].length == membershipHistoryPageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final rows = await _source.loadHistory(
      offset: _history.length,
      limit: membershipHistoryPageSize,
    );
    if (!mounted) return;
    setState(() {
      _history.addAll(rows);
      _hasMore = rows.length == membershipHistoryPageSize;
      _loadingMore = false;
    });
  }

  Future<void> _openDetail(Map<String, dynamic> membership) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .55),
        builder: (_) => FractionallySizedBox(
          heightFactor: .92,
          child: MembershipDetailSheet(
            membership: membership,
            dataSource: _source,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    final children = <Widget>[];
    void addSection(String label, List<Map<String, dynamic>> rows) {
      if (rows.isEmpty) return;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.lg));
      }
      children.add(_SectionTitle(label: label));
      children.add(const SizedBox(height: AppSpacing.xs));
      children.addAll(
        rows.map(
          (membership) => _MembershipRow(
            membership: membership,
            onTap: () => _openDetail(membership),
          ),
        ),
      );
    }

    if (widget.includeActive) {
      addSection(appStrings.currentMembership.toUpperCase(), _active);
    }
    addSection(appStrings.pick('UPCOMING', 'PRÓXIMAS'), _scheduled);
    addSection(appStrings.pick('HISTORY', 'HISTORIAL'), _history);
    if (children.isEmpty) {
      return _EmptyMessage(message: appStrings.noActivePlan);
    }
    if (_hasMore) {
      children.add(const SizedBox(height: AppSpacing.sm));
      children.add(
        OutlinedButton(
          key: const ValueKey('admin-memberships-load-more'),
          onPressed: _loadingMore ? null : _loadMore,
          child: Text(appStrings.showMore.toUpperCase()),
        ),
      );
    }
    return Column(
      key: const ValueKey('admin-member-memberships'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class MembershipDetailSheet extends StatefulWidget {
  const MembershipDetailSheet({
    super.key,
    required this.membership,
    required this.dataSource,
  });

  final Map<String, dynamic> membership;
  final UserMembershipsDataSource dataSource;

  @override
  State<MembershipDetailSheet> createState() => _MembershipDetailSheetState();
}

class _MembershipDetailSheetState extends State<MembershipDetailSheet> {
  final List<Map<String, dynamic>> _usage = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final rows = await widget.dataSource.loadUsage(
      membershipId: widget.membership['id'].toString(),
      offset: 0,
      limit: membershipUsagePageSize,
    );
    if (!mounted) return;
    setState(() {
      _usage.addAll(rows);
      _hasMore = rows.length == membershipUsagePageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final rows = await widget.dataSource.loadUsage(
      membershipId: widget.membership['id'].toString(),
      offset: _usage.length,
      limit: membershipUsagePageSize,
    );
    if (!mounted) return;
    setState(() {
      _usage.addAll(rows);
      _hasMore = rows.length == membershipUsagePageSize;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final membership = widget.membership;
    return Material(
      key: const ValueKey('membership-detail-sheet'),
      color: AppColors.surface(context),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenX,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    appStrings.pick('MEMBERSHIP', 'MEMBRESÍA'),
                    style: AppTypography.itemTitle(context),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: Navigator.of(context).pop,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                AppSpacing.md,
                AppSpacing.screenX,
                AppSpacing.xl,
              ),
              children: [
                Text(
                  _planName(membership).toUpperCase(),
                  style: AppTypography.itemTitle(
                    context,
                  ).copyWith(fontSize: 24),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _statusLabel(membership['status']?.toString()),
                  style: AppTypography.body(context).copyWith(
                    color: membership['status'] == 'active'
                        ? AppColors.primary
                        : AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _DetailValue(
                  label: appStrings.starts,
                  value: _date(context, membershipDate(membership)),
                ),
                _DetailValue(
                  label: appStrings.expires,
                  value: _date(context, membershipEndDate(membership)),
                ),
                if (!_isUnlimited(membership)) ...[
                  _DetailValue(
                    label: appStrings.pick(
                      'Initial credits',
                      'Créditos iniciales',
                    ),
                    value: '${_totalCredits(membership) ?? '—'}',
                  ),
                  _DetailValue(
                    label: appStrings.pick(
                      'Credits available',
                      'Créditos disponibles',
                    ),
                    value: '${_remainingCredits(membership) ?? '—'}',
                  ),
                  _DetailValue(
                    label: appStrings.pick(
                      'Credits used',
                      'Créditos utilizados',
                    ),
                    value: '${_usedCredits(membership) ?? '—'}',
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _SectionTitle(
                  label: _isUnlimited(membership)
                      ? appStrings.pick(
                          'CLASSES DURING THIS MEMBERSHIP',
                          'CLASES DURANTE ESTA MEMBRESÍA',
                        )
                      : appStrings.pick('USAGE', 'UTILIZACIÓN'),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                else if (_usage.isEmpty)
                  _EmptyMessage(
                    message: appStrings.pick(
                      'There is no usage registered for this membership.',
                      'No hay utilización registrada para esta membresía.',
                    ),
                  )
                else
                  ..._usage.map((row) => _UsageRow(row: row)),
                if (_hasMore && !_loading) ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    key: const ValueKey('membership-usage-load-more'),
                    onPressed: _loadingMore ? null : _loadMore,
                    child: _loadingMore
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Text(appStrings.showMore.toUpperCase()),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: AppTypography.bodySecondary(context)),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTypography.body(context),
          ),
        ),
      ],
    ),
  );
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final rawClass = row['classes'];
    final klass = rawClass is Map
        ? Map<String, dynamic>.from(rawClass)
        : const <String, dynamic>{};
    final rawProgram = klass['programs'];
    final program = rawProgram is Map
        ? Map<String, dynamic>.from(rawProgram)
        : const <String, dynamic>{};
    final startsAt = DateTime.tryParse(
      klass['starts_at']?.toString() ?? '',
    )?.toLocal();
    final title = program['name']?.toString().trim();
    final classTitle = klass['title']?.toString().trim();
    return Container(
      key: ValueKey('membership-usage-${row['id']}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: .7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title?.isNotEmpty == true
                ? title!
                : classTitle?.isNotEmpty == true
                ? classTitle!
                : appStrings.classFallback,
            style: AppTypography.body(context),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            startsAt == null
                ? '—'
                : DateFormat(
                    'd MMM yyyy · HH:mm',
                    Localizations.localeOf(context).languageCode,
                  ).format(startsAt),
            style: AppTypography.bodySecondary(context),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _bookingStatus(row['status']?.toString()),
            style: AppTypography.helper(context),
          ),
        ],
      ),
    );
  }

  String _bookingStatus(String? status) => switch (status) {
    'attended' => appStrings.pick('Attended', 'Asistió'),
    'no_show' => appStrings.pick('No-show', 'No asistió'),
    'booked' => appStrings.pick('Booked', 'Reservado'),
    _ => status ?? '—',
  };
}
