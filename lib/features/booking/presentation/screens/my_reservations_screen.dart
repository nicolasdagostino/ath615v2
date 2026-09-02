import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/preferences/app_preferences_controller.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_async_state.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_detail_header.dart';
import '../../../../core/widgets/app_section_chip.dart';
import '../../data/my_reservations_data_source.dart';
import '../widgets/class_details_sheet.dart';

class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({
    super.key,
    this.dataSource,
    this.client,
    this.onOpenForTesting,
  });

  final MyReservationsDataSource? dataSource;
  final SupabaseClient? client;
  @visibleForTesting
  final ValueChanged<Map<String, dynamic>>? onOpenForTesting;

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  late final SupabaseClient _client;
  late final MyReservationsDataSource _source;
  var _upcoming = <Map<String, dynamic>>[];
  var _history = <Map<String, dynamic>>[];
  var _showUpcoming = true;
  var _loading = true;
  var _loadingMore = false;
  var _hasMoreHistory = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? Supabase.instance.client;
    _source = widget.dataSource ?? SupabaseMyReservationsDataSource(_client);
    _loadUpcoming();
  }

  Future<void> _loadUpcoming() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _source.loadUpcoming();
      if (!mounted) return;
      setState(() => _upcoming = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showHistory() async {
    setState(() => _showUpcoming = false);
    if (_history.isNotEmpty || !_hasMoreHistory) return;
    await _loadHistory(reset: true);
  }

  Future<void> _loadHistory({bool reset = false}) async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      if (reset) {
        _loading = true;
        _error = null;
      }
    });
    try {
      final offset = reset ? 0 : _history.length;
      final rows = await _source.loadHistory(offset: offset);
      if (!mounted) return;
      setState(() {
        _history = reset ? rows : [..._history, ...rows];
        _hasMoreHistory = rows.length == bookingHistoryPageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _cancelBooking(Map<String, dynamic> row) async {
    try {
      await _client.rpc(
        'cancel_my_booking',
        params: {'p_class_id': row['id'].toString()},
      );
      await _loadUpcoming();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.bookingCancelError(error))),
      );
    }
  }

  Future<void> _leaveWaitlist(Map<String, dynamic> row) async {
    try {
      await _client.rpc(
        'leave_class_waitlist',
        params: {'p_class_id': row['id'].toString()},
      );
      await _loadUpcoming();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingWaitlistError)));
    }
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    if (widget.onOpenForTesting != null) {
      widget.onOpenForTesting!(row);
      return;
    }
    final kind = row['reservation_kind']?.toString();
    final history = !_showUpcoming;
    final actionLabel = history
        ? _statusLabel(row['reservation_status']?.toString())
        : kind == 'waitlist'
        ? appStrings.bookingLeaveWaitlist
        : appStrings.bookingCancel;
    await showClassDetailsSheet(
      context: context,
      client: _client,
      klass: row,
      actionLabel: actionLabel,
      onAction: history
          ? null
          : kind == 'waitlist'
          ? () => _leaveWaitlist(row)
          : () => _cancelBooking(row),
    );
  }

  String _statusLabel(String? status) => switch (status) {
    'attended' => appStrings.attended,
    'no_show' => appStrings.noShow,
    'cancelled' => appStrings.cancelled,
    _ => appStrings.reserved,
  };

  @override
  Widget build(BuildContext context) {
    final rows = _showUpcoming ? _upcoming : _history;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
            AppDetailHeader(
              title: appStrings.myUpcomingBookings,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                AppSpacing.xs,
                AppSpacing.screenX,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AppSectionChip(
                      key: const ValueKey('reservations-upcoming-chip'),
                      label: appStrings.upcoming,
                      selected: _showUpcoming,
                      onTap: () {
                        if (!_showUpcoming) {
                          setState(() => _showUpcoming = true);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppSectionChip(
                      key: const ValueKey('reservations-history-chip'),
                      label: appStrings.history,
                      selected: !_showUpcoming,
                      onTap: _showHistory,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const AppCenteredLoadingIndicator()
                  : _error != null
                  ? AppAsyncState.error(
                      message: appStrings.bookingLoadError(_error!),
                      actionLabel: appStrings.retry,
                      onAction: _showUpcoming
                          ? _loadUpcoming
                          : () => _loadHistory(reset: true),
                    )
                  : rows.isEmpty
                  ? _ReservationsEmpty(history: !_showUpcoming)
                  : ListView.separated(
                      key: ValueKey(
                        _showUpcoming
                            ? 'upcoming-reservations-list'
                            : 'booking-history-list',
                      ),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenX,
                        0,
                        AppSpacing.screenX,
                        AppSpacing.xl,
                      ),
                      itemCount:
                          rows.length +
                          (!_showUpcoming && _hasMoreHistory ? 1 : 0),
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: AppColors.border(context)),
                      itemBuilder: (context, index) {
                        if (index == rows.length) {
                          return TextButton(
                            key: const ValueKey('booking-history-load-more'),
                            onPressed: _loadingMore ? null : _loadHistory,
                            child: Text(
                              appStrings.loadMore.toUpperCase(),
                              style: AppTypography.body(context).copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        return _ReservationRow(
                          row: rows[index],
                          onTap: () => _openDetail(rows[index]),
                          statusLabel: _showUpcoming
                              ? rows[index]['reservation_kind'] == 'waitlist'
                                    ? appStrings.waitlist
                                    : appStrings.reserved
                              : _statusLabel(
                                  rows[index]['reservation_status']?.toString(),
                                ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _ReservationRow extends StatelessWidget {
  const _ReservationRow({
    required this.row,
    required this.onTap,
    required this.statusLabel,
  });

  final Map<String, dynamic> row;
  final VoidCallback onTap;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final startsAt = DateTime.parse(row['starts_at'].toString()).toLocal();
    final program = row['programs'];
    final programName = program is Map
        ? program['name']?.toString().trim()
        : null;
    final description = row['title']?.toString().trim() ?? '';
    final coach = row['coach'];
    final coachName = coach is Map
        ? coach['full_name']?.toString().trim()
        : null;
    final waitlistPosition = row['waitlist_position'] as int?;
    final locale = appStrings.isEs ? 'es' : 'en';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatShortMonthDay(startsAt).toUpperCase(),
                    style: AppTypography.helper(context),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    appPreferencesController.formatTime(
                      startsAt,
                      locale: locale,
                    ),
                    style: AppTypography.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (programName?.isNotEmpty == true
                            ? programName!
                            : description)
                        .toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (programName?.isNotEmpty == true &&
                      description.isNotEmpty &&
                      description != programName) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySecondary(context),
                    ),
                  ],
                  if (coachName?.isNotEmpty == true) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(coachName!, style: AppTypography.helper(context)),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    waitlistPosition == null
                        ? statusLabel.toUpperCase()
                        : '${statusLabel.toUpperCase()} · #$waitlistPosition',
                    style: AppTypography.helper(context).copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
}

class _ReservationsEmpty extends StatelessWidget {
  const _ReservationsEmpty({required this.history});

  final bool history;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        history ? appStrings.noBookingHistory : appStrings.noUpcomingBookings,
        textAlign: TextAlign.center,
        style: AppTypography.bodySecondary(context),
      ),
    ),
  );
}
