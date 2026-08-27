import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_async_state.dart';
import '../../../core/widgets/app_section_chip.dart';
import '../data/analytics_repository.dart';
import '../domain/analytics_models.dart';

enum AnalyticsSection { overview, attendance, memberships, revenue }

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key, this.repository});

  @visibleForTesting
  final AnalyticsRepository? repository;

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  late final AnalyticsRepository _repository =
      widget.repository ??
      SupabaseAnalyticsRepository(Supabase.instance.client);
  AnalyticsSection _section = AnalyticsSection.overview;
  AnalyticsPeriod _period = AnalyticsPeriod.thirtyDays;
  AnalyticsOverview? _overview;
  AttendanceAnalytics? _attendance;
  MembershipAnalytics? _memberships;
  RevenueAnalytics? _revenue;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (_section) {
        case AnalyticsSection.overview:
          final result = await _repository.loadOverview(_period);
          if (!mounted) return;
          setState(() => _overview = result);
        case AnalyticsSection.attendance:
          final result = await _repository.loadAttendance(_period);
          if (!mounted) return;
          setState(() => _attendance = result);
        case AnalyticsSection.memberships:
          final result = await _repository.loadMemberships(_period);
          if (!mounted) return;
          setState(() => _memberships = result);
        case AnalyticsSection.revenue:
          final result = await _repository.loadRevenue(_period);
          if (!mounted) return;
          setState(() => _revenue = result);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectSection(AnalyticsSection value) {
    if (_section == value) return;
    setState(() => _section = value);
    _load();
  }

  void _selectPeriod(AnalyticsPeriod value) {
    if (_period == value) return;
    setState(() => _period = value);
    _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        appStrings.analyticsTitle.toUpperCase(),
        style: AppTypography.sectionTitle(context),
      ),
      const SizedBox(height: AppSpacing.sm),
      SingleChildScrollView(
        key: const ValueKey('analytics-section-selector'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: AnalyticsSection.values.map((section) {
            final label = switch (section) {
              AnalyticsSection.overview => appStrings.analyticsOverview,
              AnalyticsSection.attendance => appStrings.analyticsAttendance,
              AnalyticsSection.memberships => appStrings.analyticsMemberships,
              AnalyticsSection.revenue => appStrings.analyticsRevenue,
            };
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: AppSectionChip(
                label: label.toUpperCase(),
                selected: _section == section,
                onTap: () => _selectSection(section),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _PeriodSelector(selected: _period, onSelected: _selectPeriod),
      const SizedBox(height: AppSpacing.lg),
      if (_loading)
        AppAsyncState.loading(message: appStrings.analyticsLoading)
      else if (_error != null)
        AppAsyncState.error(
          message: appStrings.analyticsLoadError,
          actionLabel: appStrings.retry,
          onAction: _load,
        )
      else if (_section == AnalyticsSection.overview && _overview != null)
        AnalyticsOverviewContent(data: _overview!)
      else if (_section == AnalyticsSection.attendance && _attendance != null)
        AnalyticsAttendanceContent(data: _attendance!)
      else if (_section == AnalyticsSection.memberships && _memberships != null)
        AnalyticsMembershipContent(data: _memberships!)
      else if (_section == AnalyticsSection.revenue && _revenue != null)
        AnalyticsRevenueContent(data: _revenue!),
    ],
  );
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onSelected});

  final AnalyticsPeriod selected;
  final ValueChanged<AnalyticsPeriod> onSelected;

  String _label(AnalyticsPeriod value) => switch (value) {
    AnalyticsPeriod.sevenDays => appStrings.analyticsSevenDays,
    AnalyticsPeriod.thirtyDays => appStrings.analyticsThirtyDays,
    AnalyticsPeriod.thisMonth => appStrings.analyticsThisMonth,
    AnalyticsPeriod.previousMonth => appStrings.analyticsPreviousMonth,
    AnalyticsPeriod.threeMonths => appStrings.analyticsThreeMonths,
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('analytics-period-selector'),
    scrollDirection: Axis.horizontal,
    child: Row(
      children: AnalyticsPeriod.values
          .map(
            (value) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: AppSectionChip(
                label: _label(value),
                selected: selected == value,
                onTap: () => onSelected(value),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class AnalyticsOverviewContent extends StatelessWidget {
  const AnalyticsOverviewContent({super.key, required this.data});

  final AnalyticsOverview data;

  @override
  Widget build(BuildContext context) {
    final current = data.current;
    final previous = data.previous;
    return Column(
      key: const ValueKey('analytics-overview-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 180,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
          ),
          children: [
            _KpiTile(
              label: appStrings.analyticsActiveMembers,
              value: '${current.activeMembers}',
            ),
            _KpiTile(
              label: appStrings.analyticsAttendances,
              value: '${current.attendances}',
              comparison: _countComparison(
                current.attendances,
                previous.attendances,
              ),
            ),
            _KpiTile(
              label: appStrings.analyticsOccupancy,
              value: _percent(current.globalOccupancy),
              comparison: _occupancyComparison(
                current.globalOccupancy,
                previous.globalOccupancy,
              ),
            ),
            _KpiTile(
              label: appStrings.analyticsBookings,
              value: '${current.bookings}',
              comparison: _countComparison(current.bookings, previous.bookings),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(appStrings.analyticsPeriodActivity),
        _MetricRow(
          label: appStrings.analyticsNewMembers,
          value: '${current.newMembers}',
          comparison: _countComparison(current.newMembers, previous.newMembers),
        ),
        _MetricRow(
          label: appStrings.analyticsDeliveredClasses,
          value: '${current.deliveredClasses}',
          comparison: _countComparison(
            current.deliveredClasses,
            previous.deliveredClasses,
          ),
        ),
        _MetricRow(
          label: appStrings.analyticsNoShows,
          value: '${current.noShows}',
          comparison: _countComparison(current.noShows, previous.noShows),
        ),
        _MetricRow(
          label: appStrings.analyticsAverageOccupancy,
          value: _percent(current.averageClassOccupancy),
          comparison: _occupancyComparison(
            current.averageClassOccupancy,
            previous.averageClassOccupancy,
          ),
        ),
      ],
    );
  }
}

class AnalyticsAttendanceContent extends StatelessWidget {
  const AnalyticsAttendanceContent({super.key, required this.data});

  final AttendanceAnalytics data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return AppAsyncState.empty(
        message: appStrings.analyticsNoActivity,
        icon: Icons.query_stats_rounded,
      );
    }
    return Column(
      key: const ValueKey('analytics-attendance-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(appStrings.analyticsTrend),
        _TrendChart(points: data.trend),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(appStrings.analyticsPrograms),
        _BreakdownList(rows: data.programs),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(appStrings.analyticsDays),
        _BreakdownList(
          rows: data.weekdays,
          labelBuilder: (row) => _weekdayLabel(row.weekday ?? 1),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(appStrings.analyticsHours),
        _BreakdownList(
          rows: data.hours,
          labelBuilder: (row) => '${row.hour.toString().padLeft(2, '0')}:00',
        ),
        const SizedBox(height: AppSpacing.lg),
        _ClassRanking(
          title: appStrings.analyticsMostOccupied,
          rows: data.mostOccupiedClasses,
        ),
        const SizedBox(height: AppSpacing.lg),
        _ClassRanking(
          title: appStrings.analyticsLeastOccupied,
          rows: data.leastOccupiedClasses,
        ),
      ],
    );
  }
}

class AnalyticsMembershipContent extends StatelessWidget {
  const AnalyticsMembershipContent({super.key, required this.data});

  final MembershipAnalytics data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return AppAsyncState.empty(
        message: appStrings.analyticsNoMemberships,
        icon: Icons.card_membership_outlined,
      );
    }
    final snapshot = data.snapshot;
    final credits = data.credits;
    return Column(
      key: const ValueKey('analytics-memberships-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 180,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
          ),
          children: [
            _KpiTile(
              label: appStrings.activeMemberships,
              value: '${snapshot.active}',
            ),
            _KpiTile(
              label: appStrings.analyticsActivePacks,
              value: '${snapshot.activePacks}',
            ),
            _KpiTile(
              label: appStrings.analyticsActiveUnlimited,
              value: '${snapshot.activeUnlimited}',
            ),
            _KpiTile(
              label: appStrings.analyticsNewMemberships,
              value: '${data.created}',
              comparison: _countComparison(data.created, data.previousCreated),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(appStrings.analyticsCurrentStatus),
        _CompactMetrics(
          rows: [
            (appStrings.analyticsScheduled, snapshot.scheduled.toString()),
            (appStrings.analyticsExhausted, snapshot.exhausted.toString()),
            (appStrings.analyticsExpired, snapshot.expired.toString()),
            (appStrings.analyticsCancelled, snapshot.cancelled.toString()),
            (appStrings.analyticsReplaced, snapshot.replaced.toString()),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(appStrings.analyticsPacksVsUnlimited),
        _DistributionBars(
          rows: [
            (appStrings.analyticsPacks, snapshot.activePacks),
            (appStrings.analyticsUnlimited, snapshot.activeUnlimited),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(appStrings.analyticsPlans),
        _MembershipPlanRanking(rows: data.plans),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(appStrings.analyticsCredits),
        _CompactMetrics(
          rows: [
            (
              appStrings.analyticsCreditsPurchased,
              '${credits.purchasedGranted}',
            ),
            (appStrings.analyticsCreditsAssigned, '${credits.assignedGranted}'),
            (appStrings.analyticsCreditsConsumed, '${credits.consumed}'),
            (appStrings.analyticsCreditsRefunded, '${credits.refunded}'),
            (appStrings.analyticsNetConsumption, '${credits.netConsumed}'),
            (
              appStrings.analyticsCreditsRemaining,
              '${credits.currentRemaining}',
            ),
            (
              appStrings.analyticsCreditsExpiredUnused,
              '${credits.expiredUnused}',
            ),
          ],
        ),
      ],
    );
  }
}

class AnalyticsRevenueContent extends StatelessWidget {
  const AnalyticsRevenueContent({super.key, required this.data});

  final RevenueAnalytics data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return AppAsyncState.empty(
        message: appStrings.analyticsNoConfirmedPayments,
        icon: Icons.payments_outlined,
      );
    }
    return Column(
      key: const ValueKey('analytics-revenue-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...data.currencies.map((currency) {
          final methods = data.methods
              .where((row) => row.currency == currency.currency)
              .toList();
          final plans = data.plans
              .where((row) => row.currency == currency.currency)
              .toList();
          final trend = data.trend
              .where((row) => row.currency == currency.currency)
              .toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.currencies.length > 1)
                  _SectionLabel(currency.currency),
                GridView(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                  mainAxisExtent: 185,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                  ),
                  children: [
                    _KpiTile(
                      label: appStrings.analyticsCollected,
                      value: _money(currency.totalMinor, currency.currency),
                      comparison: _moneyComparison(
                        currency.totalMinor,
                        currency.previousTotalMinor,
                      ),
                    ),
                    _KpiTile(
                      label: appStrings.analyticsConfirmedPayments,
                      value: '${currency.paymentCount}',
                      comparison: _countComparison(
                        currency.paymentCount,
                        currency.previousPaymentCount,
                      ),
                    ),
                    _KpiTile(
                      label: appStrings.analyticsAverageTicket,
                      value: _money(currency.averageMinor, currency.currency),
                      comparison: currency.previousAverageMinor == null
                          ? _Comparison(appStrings.analyticsNoComparable, 0)
                          : _moneyComparison(
                              currency.averageMinor,
                              currency.previousAverageMinor!,
                            ),
                    ),
                    _KpiTile(
                      label: appStrings.analyticsTopRevenuePlan,
                      value: plans.isEmpty ? '—' : plans.first.name,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SectionLabel(appStrings.analyticsRevenueTrend),
                _RevenueTrendChart(points: trend),
                const SizedBox(height: AppSpacing.lg),
                _SectionLabel(appStrings.analyticsPaymentMethod),
                _RevenueMethodBars(rows: methods, currency: currency.currency),
                const SizedBox(height: AppSpacing.lg),
                _SectionLabel(appStrings.analyticsRevenueByPlan),
                _RevenuePlanRanking(rows: plans),
              ],
            ),
          );
        }),
        _RevenueStates(data: data),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value, this.comparison});

  final String label;
  final String value;
  final _Comparison? comparison;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppRadii.panel),
      border: Border.all(color: AppColors.border(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label.toUpperCase(), style: AppTypography.helper(context)),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: AppTypography.itemTitle(
            context,
          ).copyWith(color: AppColors.primary, fontSize: 27),
        ),
        if (comparison != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            comparison!.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.helper(
              context,
            ).copyWith(color: comparison!.color(context), fontSize: 11),
          ),
        ],
      ],
    ),
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.comparison,
  });

  final String label;
  final String value;
  final _Comparison comparison;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border(context))),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.body(context))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: AppTypography.body(context)),
              Text(
                comparison.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppTypography.helper(
                  context,
                ).copyWith(color: comparison.color(context)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      label.toUpperCase(),
      style: AppTypography.sectionTitle(context),
    ),
  );
}

class _CompactMetrics extends StatelessWidget {
  const _CompactMetrics({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Column(
    children: rows
        .map(
          (row) => Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(row.$1, style: AppTypography.body(context)),
                ),
                Text(
                  row.$2,
                  style: AppTypography.body(
                    context,
                  ).copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

class _DistributionBars extends StatelessWidget {
  const _DistributionBars({required this.rows});
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<int>(0, (sum, row) => sum + row.$2);
    if (total == 0) {
      return Text(
        appStrings.analyticsNoMemberships,
        style: AppTypography.bodySecondary(context),
      );
    }
    return Column(
      children: rows.map((row) {
        final percentage = 100 * row.$2 / total;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(row.$1, style: AppTypography.body(context)),
                  ),
                  Text(
                    '${row.$2} · ${percentage.toStringAsFixed(0)}%',
                    style: AppTypography.helper(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: row.$2 / total,
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MembershipPlanRanking extends StatelessWidget {
  const _MembershipPlanRanking({required this.rows});
  final List<MembershipPlanAnalytics> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        appStrings.analyticsNoMemberships,
        style: AppTypography.bodySecondary(context),
      );
    }
    return Column(
      children: rows
          .take(8)
          .map(
            (row) => Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border(context)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(row.name, style: AppTypography.body(context)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    appStrings.analyticsPlanMembershipSummary(
                      row.membershipsCreated,
                      row.paidSales,
                      row.directAssignments,
                    ),
                    textAlign: TextAlign.end,
                    style: AppTypography.helper(context),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _RevenueMethodBars extends StatelessWidget {
  const _RevenueMethodBars({required this.rows, required this.currency});
  final List<RevenueMethodAnalytics> rows;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        appStrings.analyticsNoClassifiedMethods,
        style: AppTypography.bodySecondary(context),
      );
    }
    final maxValue = rows.fold<int>(
      1,
      (value, row) => math.max(value, row.totalMinor),
    );
    return Column(
      children: rows
          .map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _paymentMethodLabel(row.method),
                          style: AppTypography.body(context),
                        ),
                      ),
                      Text(
                        '${_money(row.totalMinor, currency)} · ${row.paymentCount}',
                        style: AppTypography.helper(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  FractionallySizedBox(
                    widthFactor: row.totalMinor / maxValue,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _RevenuePlanRanking extends StatelessWidget {
  const _RevenuePlanRanking({required this.rows});
  final List<RevenuePlanAnalytics> rows;

  @override
  Widget build(BuildContext context) => rows.isEmpty
      ? Text(
          appStrings.analyticsNoConfirmedPayments,
          style: AppTypography.bodySecondary(context),
        )
      : Column(
          children: rows
              .take(8)
              .map(
                (row) => Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.border(context)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.name, style: AppTypography.body(context)),
                            Text(
                              appStrings.analyticsPaymentCount(
                                row.paymentCount,
                              ),
                              style: AppTypography.helper(context),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _money(row.revenueMinor, row.currency),
                            style: AppTypography.body(
                              context,
                            ).copyWith(color: AppColors.primary),
                          ),
                          Text(
                            '${row.revenueShare?.toStringAsFixed(1) ?? '—'}%',
                            style: AppTypography.helper(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
}

class _RevenueStates extends StatelessWidget {
  const _RevenueStates({required this.data});
  final RevenueAnalytics data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionLabel(appStrings.analyticsPaymentStates),
      _CompactMetrics(
        rows: [
          (appStrings.analyticsPaid, '${data.states.paid}'),
          (appStrings.analyticsPending, '${data.states.pending}'),
          (appStrings.analyticsFailed, '${data.states.failed}'),
          (appStrings.analyticsCancelled, '${data.states.cancelled}'),
        ],
      ),
    ],
  );
}

class _RevenueTrendChart extends StatelessWidget {
  const _RevenueTrendChart({required this.points});
  final List<RevenueTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Text(
        appStrings.analyticsNoConfirmedPayments,
        style: AppTypography.bodySecondary(context),
      );
    }
    final maxValue = points.fold<int>(
      1,
      (value, point) => math.max(value, point.totalMinor),
    );
    return Container(
      key: const ValueKey('analytics-revenue-chart'),
      height: 170,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points
            .map(
              (point) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Tooltip(
                    message:
                        '${DateFormat.MMMd(appStrings.isEs ? 'es' : 'en').format(point.date)} · ${_money(point.totalMinor, point.currency)}',
                    child: FractionallySizedBox(
                      heightFactor: math.max(0.04, point.totalMinor / maxValue),
                      alignment: Alignment.bottomCenter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _BreakdownList extends StatelessWidget {
  const _BreakdownList({required this.rows, this.labelBuilder});

  final List<AnalyticsBreakdownRow> rows;
  final String Function(AnalyticsBreakdownRow row)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        appStrings.analyticsNoActivity,
        style: AppTypography.bodySecondary(context),
      );
    }
    final maxBookings = rows.fold<int>(
      1,
      (max, row) => math.max(max, row.bookings),
    );
    return Column(
      children: rows.take(8).map((row) {
        final label = labelBuilder?.call(row) ?? row.label;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label, style: AppTypography.body(context)),
                  ),
                  Text(
                    _percent(row.occupancy),
                    style: AppTypography.helper(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              FractionallySizedBox(
                widthFactor: row.bookings / maxBookings,
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                appStrings.analyticsBookingsAndAttendances(
                  row.bookings,
                  row.attendances,
                ),
                style: AppTypography.helper(context),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ClassRanking extends StatelessWidget {
  const _ClassRanking({required this.title, required this.rows});
  final String title;
  final List<AnalyticsClassRow> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionLabel(title),
      if (rows.isEmpty)
        Text(
          appStrings.analyticsNoActivity,
          style: AppTypography.bodySecondary(context),
        )
      else
        ...rows.map(
          (row) => Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.programName, style: AppTypography.body(context)),
                      Text(
                        '${DateFormat.MMMd(appStrings.isEs ? 'es' : 'en').format(row.date)} · ${row.hour.toString().padLeft(2, '0')}:00',
                        style: AppTypography.helper(context),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _percent(row.occupancy),
                      style: AppTypography.body(
                        context,
                      ).copyWith(color: AppColors.primary),
                    ),
                    Text(
                      appStrings.analyticsClassCapacity(
                        row.bookings,
                        row.capacity,
                      ),
                      style: AppTypography.helper(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});
  final List<AnalyticsTrendPoint> points;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('analytics-trend-chart'),
    height: 180,
    padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      border: Border.all(color: AppColors.border(context)),
      borderRadius: BorderRadius.circular(AppRadii.panel),
    ),
    child: Column(
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          runSpacing: AppSpacing.xxs,
          children: [
            _Legend(
              color: AppColors.primary,
              label: appStrings.analyticsBookings,
            ),
            const SizedBox(width: AppSpacing.sm),
            _Legend(
              color: AppColors.success,
              label: appStrings.analyticsAttendances,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: CustomPaint(
            painter: _TrendPainter(
              points: points,
              bookingsColor: AppColors.primary,
              attendanceColor: AppColors.success,
              gridColor: AppColors.border(context),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 3, color: color),
      const SizedBox(width: 4),
      Text(label, style: AppTypography.helper(context)),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.bookingsColor,
    required this.attendanceColor,
    required this.gridColor,
  });
  final List<AnalyticsTrendPoint> points;
  final Color bookingsColor;
  final Color attendanceColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = gridColor,
    );
    if (points.length < 2) return;
    final maxValue = points.fold<int>(
      1,
      (value, point) =>
          math.max(value, math.max(point.bookings, point.attendances)),
    );
    Path pathFor(int Function(AnalyticsTrendPoint) valueOf) {
      final path = Path();
      for (var index = 0; index < points.length; index++) {
        final x = size.width * index / (points.length - 1);
        final y = size.height * (1 - valueOf(points[index]) / maxValue);
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    canvas.drawPath(
      pathFor((point) => point.bookings),
      Paint()
        ..color = bookingsColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      pathFor((point) => point.attendances),
      Paint()
        ..color = attendanceColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.bookingsColor != bookingsColor ||
      oldDelegate.attendanceColor != attendanceColor ||
      oldDelegate.gridColor != gridColor;
}

class _Comparison {
  const _Comparison(this.label, this.direction);
  final String label;
  final int direction;
  Color color(BuildContext context) => direction == 0
      ? AppColors.textSecondary(context)
      : direction > 0
      ? AppColors.success
      : AppColors.danger;
}

_Comparison _countComparison(int current, int previous) {
  if (previous == 0) {
    return _Comparison(appStrings.analyticsNoComparable, 0);
  }
  final change = ((current - previous) * 100 / previous);
  if (change.abs() < 0.05) {
    return _Comparison(appStrings.analyticsComparedSame, 0);
  }
  final value = '${change.abs().toStringAsFixed(0)}%';
  return _Comparison(
    change > 0
        ? appStrings.analyticsComparedUp(value)
        : appStrings.analyticsComparedDown(value),
    change > 0 ? 1 : -1,
  );
}

_Comparison _occupancyComparison(double? current, double? previous) {
  if (current == null || previous == null || previous == 0) {
    return _Comparison(appStrings.analyticsNoComparable, 0);
  }
  final change = current - previous;
  if (change.abs() < 0.05) {
    return _Comparison(appStrings.analyticsComparedSame, 0);
  }
  final value = '${change.abs().toStringAsFixed(1)} pp';
  return _Comparison(
    change > 0
        ? appStrings.analyticsComparedUp(value)
        : appStrings.analyticsComparedDown(value),
    change > 0 ? 1 : -1,
  );
}

_Comparison _moneyComparison(int current, int previous) =>
    _countComparison(current, previous);

String _money(int minor, String currency) {
  final locale = appStrings.isEs ? 'es_ES' : 'en_US';
  try {
    return NumberFormat.simpleCurrency(
      name: currency,
      locale: locale,
    ).format(minor / 100);
  } catch (_) {
    return '$currency ${(minor / 100).toStringAsFixed(2)}';
  }
}

String _paymentMethodLabel(String method) => switch (method) {
  'card' => appStrings.analyticsCard,
  'cash' => appStrings.cash,
  'bizum' => appStrings.bizum,
  _ => method,
};

String _percent(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(1)}%';

String _weekdayLabel(int weekday) {
  final monday = DateTime(2026, 8, 24);
  return DateFormat.EEEE(
    appStrings.isEs ? 'es' : 'en',
  ).format(monday.add(Duration(days: weekday - 1)));
}
