import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_async_state.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_primary_gym_header.dart';
import '../../data/coach_briefing_repository.dart';

Future<void> showCoachClassDetail({
  required BuildContext context,
  required CoachBriefingClass klass,
  required CoachBriefingRepository repository,
  DateTime? now,
  ValueChanged<String>? onOpenMember,
  Future<void> Function()? onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _CoachClassView(
    klass: klass,
    repository: repository,
    now: now ?? DateTime.now(),
    onOpenMember: onOpenMember,
    onChanged: onChanged ?? () async {},
  ),
);

class CoachBriefingScreen extends StatefulWidget {
  const CoachBriefingScreen({
    super.key,
    this.gymName,
    this.repository,
    this.now,
    this.onOpenMember,
    this.showHeader = true,
  });

  final String? gymName;
  final CoachBriefingRepository? repository;
  final DateTime Function()? now;
  final ValueChanged<String>? onOpenMember;
  final bool showHeader;

  @override
  State<CoachBriefingScreen> createState() => _CoachBriefingScreenState();
}

class _CoachBriefingScreenState extends State<CoachBriefingScreen> {
  late final CoachBriefingRepository _repository =
      widget.repository ??
      SupabaseCoachBriefingRepository(Supabase.instance.client);
  CoachBriefing? _briefing;
  bool _loading = true;
  String? _error;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final briefing = await _repository.loadToday();
      if (!mounted) return;
      setState(() {
        _briefing = briefing;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Daily coach briefing load failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = appStrings.pick(
          "We couldn't load today's classes. Try again.",
          'No pudimos cargar las clases de hoy. Intentá nuevamente.',
        );
      });
    }
  }

  Future<void> _openClass(CoachBriefingClass klass) async {
    await showCoachClassDetail(
      context: context,
      klass: klass,
      repository: _repository,
      now: _now,
      onOpenMember: widget.onOpenMember,
      onChanged: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        key: const ValueKey('coach-briefing-list'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.md,
          AppSpacing.screenX,
          AppSpacing.xl,
        ),
        children: [
          Text(
            appStrings.pick('TODAY', 'HOY'),
            style: AppTypography.sectionTitle(context),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (_briefing case final briefing?)
            Text(
              '${DateFormat.yMMMMd(appStrings.isEs ? 'es' : 'en').format(briefing.localDate)} · ${briefing.timezone}',
              key: const ValueKey('coach-briefing-timezone'),
              style: AppTypography.bodySecondary(context),
            ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const AppCenteredLoadingIndicator()
          else if (_error case final error?)
            AppAsyncState.error(
              message: error,
              actionLabel: appStrings.retry,
              onAction: _load,
            )
          else if (_briefing?.classes.isEmpty ?? true)
            AppAsyncState.empty(
              message: appStrings.pick(
                'No classes scheduled today.',
                'No hay clases programadas hoy.',
              ),
            )
          else
            ..._briefing!.classes.map(
              (klass) => _CoachClassRow(
                klass: klass,
                now: _now,
                onTap: () => _openClass(klass),
              ),
            ),
        ],
      ),
    );

    if (!widget.showHeader) return body;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        body: Column(
          children: [
            AppPrimaryGymHeader(gymName: widget.gymName),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _CoachClassRow extends StatelessWidget {
  const _CoachClassRow({
    required this.klass,
    required this.now,
    required this.onTap,
  });

  final CoachBriefingClass klass;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = klass.temporalStatusAt(now);
    final statusLabel = switch (status) {
      CoachClassTemporalStatus.upcoming => appStrings.pick(
        'UPCOMING',
        'PRÓXIMA',
      ),
      CoachClassTemporalStatus.inProgress => appStrings.pick(
        'IN PROGRESS',
        'EN CURSO',
      ),
      CoachClassTemporalStatus.completed => appStrings.pick(
        'COMPLETED',
        'COMPLETADA',
      ),
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('coach-class-${klass.id}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border(context), width: .7),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  klass.localStartTime,
                  style: AppTypography.itemTitle(context),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(klass.title, style: AppTypography.itemTitle(context)),
                    if (klass.coachName?.trim().isNotEmpty == true)
                      Text(
                        klass.coachName!,
                        style: AppTypography.bodySecondary(context),
                      ),
                    const SizedBox(height: AppSpacing.xxs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        _BriefingBadge(label: statusLabel),
                        _BriefingBadge(
                          label: '${klass.booked.length} / ${klass.capacity}',
                        ),
                        if (klass.waitlist.isNotEmpty)
                          _BriefingBadge(
                            label:
                                '${appStrings.waitlist} ${klass.waitlist.length}',
                          ),
                        if (klass.programName?.trim().isNotEmpty == true)
                          _BriefingBadge(label: klass.programName!),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachClassView extends StatefulWidget {
  const _CoachClassView({
    required this.klass,
    required this.repository,
    required this.now,
    required this.onChanged,
    this.onOpenMember,
  });

  final CoachBriefingClass klass;
  final CoachBriefingRepository repository;
  final DateTime now;
  final Future<void> Function() onChanged;
  final ValueChanged<String>? onOpenMember;

  @override
  State<_CoachClassView> createState() => _CoachClassViewState();
}

class _CoachClassViewState extends State<_CoachClassView> {
  late List<CoachBriefingAthlete> _booked = [...widget.klass.booked];
  bool _markingAll = false;

  Future<void> _setAttendance(CoachBriefingAthlete athlete, String next) async {
    final index = _booked.indexOf(athlete);
    final previous = athlete.attendanceStatus;
    setState(() => _booked[index] = athlete.withAttendanceStatus(next));
    try {
      final updated = await widget.repository.setAttendance(
        bookingId: athlete.bookingId,
        expectedStatus: previous,
        status: next,
      );
      if (!updated) throw StateError('attendance_conflict');
      await widget.onChanged();
    } catch (error) {
      debugPrint('Coach attendance update failed: $error');
      if (!mounted) return;
      setState(() => _booked[index] = athlete);
      _showHumanError();
    }
  }

  Future<void> _markAll() async {
    if (_markingAll) return;
    setState(() {
      _markingAll = true;
      _booked = [
        for (final athlete in _booked)
          if (!athlete.isGuest && athlete.attendanceStatus == 'booked')
            athlete.withAttendanceStatus('attended')
          else
            athlete,
      ];
    });
    try {
      await widget.repository.markAllAttended(widget.klass.id);
      await widget.onChanged();
    } catch (error) {
      debugPrint('Coach mark all attended failed: $error');
      if (!mounted) return;
      setState(() => _booked = [...widget.klass.booked]);
      _showHumanError();
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _showHumanError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          appStrings.pick(
            "We couldn't update attendance. Try again.",
            'No pudimos actualizar la asistencia. Intentá nuevamente.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final klass = widget.klass;
    final canMarkAll =
        !widget.now.toUtc().isBefore(klass.startsAt.toUtc()) &&
        _booked.any((a) => !a.isGuest && a.attendanceStatus == 'booked');
    return FractionallySizedBox(
      heightFactor: .94,
      child: Material(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text(klass.title, style: AppTypography.itemTitle(context)),
              subtitle: Text(
                '${klass.localStartTime} · ${klass.coachName ?? appStrings.coach} · ${_booked.length}/${klass.capacity}',
                style: AppTypography.bodySecondary(context),
              ),
              trailing: klass.waitlist.isEmpty
                  ? null
                  : _BriefingBadge(
                      label: '${appStrings.waitlist} ${klass.waitlist.length}',
                    ),
            ),
            Divider(height: 1, color: AppColors.border(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenX),
                children: [
                  Text('WOD', style: AppTypography.sectionTitle(context)),
                  const SizedBox(height: AppSpacing.xs),
                  if (klass.programName?.trim().isNotEmpty == true)
                    Text(
                      klass.programName!,
                      style: AppTypography.itemTitle(context),
                    ),
                  Text(
                    klass.workoutDescription?.trim().isNotEmpty == true
                        ? klass.workoutDescription!
                        : appStrings.pick(
                            'No WOD added for this class.',
                            'No hay WOD cargado para esta clase.',
                          ),
                    key: const ValueKey('coach-class-wod'),
                    style: AppTypography.body(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          appStrings.pick('BOOKED', 'RESERVADOS'),
                          style: AppTypography.sectionTitle(context),
                        ),
                      ),
                      Text(
                        '${_booked.length}',
                        style: AppTypography.helper(context),
                      ),
                    ],
                  ),
                  if (_booked.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Text(
                        appStrings.pick(
                          'No athletes booked yet.',
                          'Todavía no hay atletas reservados.',
                        ),
                        style: AppTypography.bodySecondary(context),
                      ),
                    )
                  else
                    ..._booked.map(
                      (athlete) => _CoachAthleteRow(
                        athlete: athlete,
                        now: widget.now,
                        onOpenMember: athlete.isGuest || athlete.userId == null
                            ? null
                            : () => widget.onOpenMember?.call(athlete.userId!),
                        onAttended: athlete.isGuest
                            ? null
                            : () => _setAttendance(
                                athlete,
                                athlete.attendanceStatus == 'attended'
                                    ? 'booked'
                                    : 'attended',
                              ),
                        onNoShow: athlete.isGuest
                            ? null
                            : () => _setAttendance(
                                athlete,
                                athlete.attendanceStatus == 'no_show'
                                    ? 'booked'
                                    : 'no_show',
                              ),
                      ),
                    ),
                  if (klass.waitlist.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      '${appStrings.waitlist} · ${klass.waitlist.length}',
                      style: AppTypography.sectionTitle(context),
                    ),
                    ...klass.waitlist.map(
                      (member) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text('${member.position}'),
                        title: Text(member.name),
                        onTap: widget.onOpenMember == null
                            ? null
                            : () => widget.onOpenMember!(member.userId),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (canMarkAll)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenX),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('coach-mark-all-attended'),
                      onPressed: _markingAll ? null : _markAll,
                      icon: const Icon(Icons.done_all_rounded),
                      label: Text(
                        appStrings.pick(
                          'MARK ALL ATTENDED',
                          'MARCAR TODOS PRESENTES',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoachAthleteRow extends StatelessWidget {
  const _CoachAthleteRow({
    required this.athlete,
    required this.now,
    this.onOpenMember,
    this.onAttended,
    this.onNoShow,
  });

  final CoachBriefingAthlete athlete;
  final DateTime now;
  final VoidCallback? onOpenMember;
  final VoidCallback? onAttended;
  final VoidCallback? onNoShow;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: AppColors.border(context), width: .7),
      ),
    ),
    child: Row(
      children: [
        InkWell(
          onTap: onOpenMember,
          child: CircleAvatar(
            radius: 18,
            foregroundImage: athlete.avatarUrl?.isNotEmpty == true
                ? NetworkImage(athlete.avatarUrl!)
                : null,
            child: Text(athlete.name.characters.first.toUpperCase()),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: InkWell(
            onTap: onOpenMember,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(athlete.name, style: AppTypography.body(context)),
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    if (athlete.firstClass)
                      const _BriefingBadge(label: 'FIRST CLASS'),
                    if (athlete.hasLowCredits)
                      const _BriefingBadge(label: 'LOW CREDITS'),
                    if (athlete.membershipExpiresWithin(
                      now,
                      const Duration(days: 7),
                    ))
                      const _BriefingBadge(label: 'EXPIRING'),
                    if (!athlete.isGuest && !athlete.membershipUsable)
                      const _BriefingBadge(label: 'NO MEMBERSHIP'),
                  ],
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: ValueKey('coach-attended-${athlete.bookingId}'),
          tooltip: appStrings.attended,
          onPressed: onAttended,
          color: athlete.attendanceStatus == 'attended'
              ? AppColors.primary
              : AppColors.textSecondary(context),
          icon: Icon(
            athlete.attendanceStatus == 'attended'
                ? Icons.check_circle_rounded
                : Icons.check_circle_outline_rounded,
          ),
        ),
        IconButton(
          key: ValueKey('coach-no-show-${athlete.bookingId}'),
          tooltip: appStrings.noShow,
          onPressed: onNoShow,
          color: athlete.attendanceStatus == 'no_show'
              ? AppColors.danger
              : AppColors.textSecondary(context),
          icon: const Icon(Icons.person_off_outlined),
        ),
      ],
    ),
  );
}

class _BriefingBadge extends StatelessWidget {
  const _BriefingBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Text(
      label.toUpperCase(),
      style: AppTypography.helper(
        context,
      ).copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
    ),
  );
}
