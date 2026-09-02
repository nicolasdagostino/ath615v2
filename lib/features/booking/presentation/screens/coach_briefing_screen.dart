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
import '../widgets/class_details_sheet.dart';

/// Coach's today summary. All roster operations use the shared Class Detail.
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
    setState(() {
      _loading = true;
      _error = null;
    });
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
    await showClassDetailsSheet(
      context: context,
      client: Supabase.instance.client,
      klass: {
        'id': klass.id,
        'title': klass.title,
        'starts_at': klass.startsAt.toIso8601String(),
        'duration_minutes': klass.durationMinutes,
        'capacity': klass.capacity,
        'coach_id': klass.coachId,
        'coach': {
          'full_name': klass.coachName,
          'avatar_url': klass.coachAvatarUrl,
        },
        'programs': {'name': klass.programName},
      },
      actionLabel: '',
      onAction: null,
      coachRepository: _repository,
      prefetchedIntelligence: klass,
      onMemberTap: widget.onOpenMember,
    );
    await _load();
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
    final status = switch (klass.temporalStatusAt(now)) {
      CoachClassTemporalStatus.upcoming => appStrings.classStatusUpcoming,
      CoachClassTemporalStatus.inProgress => appStrings.classStatusInProgress,
      CoachClassTemporalStatus.completed => appStrings.classStatusCompleted,
    };
    return ListTile(
      key: ValueKey('coach-class-${klass.id}'),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Text(
        klass.localStartTime,
        style: AppTypography.itemTitle(context),
      ),
      title: Text(klass.title, style: AppTypography.itemTitle(context)),
      subtitle: Text(
        [
          if (klass.coachName?.trim().isNotEmpty == true) klass.coachName!,
          status,
          '${klass.booked.length} / ${klass.capacity}',
          if (klass.waitlist.isNotEmpty)
            '${appStrings.waitlist} ${klass.waitlist.length}',
          if (klass.programName?.trim().isNotEmpty == true) klass.programName!,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySecondary(context),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.primary,
      ),
    );
  }
}
