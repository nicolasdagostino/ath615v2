import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/preferences/app_preferences_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_admin_actions.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../booking_colors.dart';
import '../../data/coach_briefing_repository.dart';
import 'attendance_admin_actions.dart';

class ClassDetailAdminAction {
  const ClassDetailAdminAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

class ClassDetailAttendeeActions {
  const ClassDetailAttendeeActions({
    required this.onAddMember,
    required this.onAddGuest,
    this.onChanged,
    this.canMarkAttendance = true,
  });

  final Future<Map<String, dynamic>?> Function(int bookingCount) onAddMember;
  final Future<Map<String, dynamic>?> Function(int bookingCount) onAddGuest;
  final Future<void> Function()? onChanged;
  final bool canMarkAttendance;
}

Future<void> showClassDetailsSheet({
  required BuildContext context,
  required SupabaseClient client,
  required Map<String, dynamic> klass,
  required String actionLabel,
  required VoidCallback? onAction,
  List<ClassDetailAdminAction> adminActions = const [],
  ClassDetailAttendeeActions? attendeeActions,
  ValueChanged<String>? onMemberTap,
  CoachBriefingRepository? coachRepository,
  CoachBriefingClass? prefetchedIntelligence,
}) async {
  final classId = klass['id'].toString();

  CoachBriefingClass? intelligence = prefetchedIntelligence;
  final operationsRepository = coachRepository;
  if (intelligence == null && operationsRepository != null) {
    try {
      final briefing = await operationsRepository.loadToday();
      intelligence = briefing.classes
          .where((candidate) => candidate.id == classId)
          .firstOrNull;
    } catch (_) {
      // Future/historical classes and unauthorized actors keep normal detail.
    }
  }

  late final List<Map<String, dynamic>> bookingRows;
  late final List<Map<String, dynamic>> waitlistRows;
  late final Map<String, Map<String, dynamic>> profileById;
  if (intelligence case final todayClass?) {
    bookingRows = [
      for (final athlete in todayClass.booked)
        {
          'id': athlete.bookingId,
          'user_id': athlete.userId,
          'guest_name': athlete.isGuest ? athlete.name : null,
          'is_guest': athlete.isGuest,
          'status': athlete.attendanceStatus,
        },
    ];
    waitlistRows = [
      for (final member in todayClass.waitlist)
        {'user_id': member.userId, 'position': member.position},
    ];
    profileById = {
      for (final athlete in todayClass.booked)
        if (athlete.userId != null)
          athlete.userId!: {
            'id': athlete.userId,
            'full_name': athlete.name,
            'avatar_url': athlete.avatarUrl,
          },
      for (final member in todayClass.waitlist)
        member.userId: {
          'id': member.userId,
          'full_name': member.name,
          'avatar_url': member.avatarUrl,
        },
    };
  } else {
    final bookings = await client
        .from('class_bookings')
        .select('id, user_id, guest_name, is_guest, status, created_at')
        .eq('class_id', classId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: true);
    final waitlist = await client
        .from('class_waitlist')
        .select('user_id, created_at')
        .eq('class_id', classId)
        .order('created_at', ascending: true);
    bookingRows = List<Map<String, dynamic>>.from(bookings);
    waitlistRows = List<Map<String, dynamic>>.from(waitlist);

    final userIds = <String>{
      if (klass['coach_id'] != null) klass['coach_id'].toString(),
      ...bookingRows
          .where((booking) => booking['user_id'] != null)
          .map((booking) => booking['user_id'].toString()),
      ...waitlistRows.map((entry) => entry['user_id'].toString()),
    }.toList();
    final profiles = userIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await client
                .from('profiles')
                .select('id, full_name, avatar_url')
                .inFilter('id', userIds),
          );
    profileById = {
      for (final profile in profiles) profile['id'].toString(): profile,
    };
  }
  final currentUserId = client.auth.currentUser?.id;
  final myWaitlistIndex = currentUserId == null
      ? -1
      : waitlistRows.indexWhere(
          (row) => row['user_id']?.toString() == currentUserId,
        );
  final myWaitlistPosition = myWaitlistIndex >= 0 ? myWaitlistIndex + 1 : null;

  Map<String, String> pinnedNotesByMember = const {};
  if (intelligence != null && operationsRepository != null) {
    final memberIds = intelligence.booked
        .map((athlete) => athlete.userId)
        .whereType<String>()
        .toSet()
        .toList();
    if (memberIds.isNotEmpty) {
      try {
        final notes = await client.rpc(
          'list_effective_member_pinned_notes',
          params: {'p_member_user_ids': memberIds},
        );
        pinnedNotesByMember = {
          for (final note in List<Map<String, dynamic>>.from(notes as List))
            note['member_user_id'].toString(): note['body'].toString(),
        };
      } catch (_) {
        // Notes are optional context; class operations remain available.
      }
    }
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        Future<void> addMember() async {
          final result = await attendeeActions?.onAddMember(bookingRows.length);
          if (result == null) return;
          final booking = Map<String, dynamic>.from(result['booking'] as Map);
          final member = Map<String, dynamic>.from(result['member'] as Map);
          final userId = member['user_id']?.toString();
          bookingRows.add(booking);
          if (userId != null) {
            profileById[userId] = {
              'id': userId,
              'full_name': member['full_name'],
              'avatar_url': member['avatar_url'],
            };
          }
          setSheetState(() {});
        }

        Future<void> addGuest() async {
          final booking = await attendeeActions?.onAddGuest(bookingRows.length);
          if (booking == null) return;
          bookingRows.add(booking);
          setSheetState(() {});
        }

        Future<void> updateAttendeeStatus(
          Map<String, dynamic> booking,
          String status,
        ) async {
          final previous = booking['status']?.toString() ?? 'booked';
          booking['status'] = status;
          setSheetState(() {});
          try {
            if (operationsRepository != null && intelligence != null) {
              final updated = await operationsRepository.setAttendance(
                bookingId: booking['id'].toString(),
                expectedStatus: previous,
                status: status,
              );
              if (!updated) throw StateError('attendance_conflict');
            } else {
              await updateClassBookingAttendance(
                client: client,
                bookingId: booking['id'].toString(),
                status: status,
              );
            }
            await attendeeActions?.onChanged?.call();
          } catch (error) {
            booking['status'] = previous;
            setSheetState(() {});
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(content: Text(appStrings.attendanceError(error))),
            );
          }
        }

        Future<void> markAllAttended() async {
          if (operationsRepository == null || intelligence == null) return;
          final previous = {
            for (final booking in bookingRows)
              booking['id'].toString(): booking['status'],
          };
          for (final booking in bookingRows) {
            if (booking['is_guest'] != true && booking['status'] == 'booked') {
              booking['status'] = 'attended';
            }
          }
          setSheetState(() {});
          try {
            await operationsRepository.markAllAttended(classId);
            await attendeeActions?.onChanged?.call();
          } catch (error) {
            for (final booking in bookingRows) {
              booking['status'] = previous[booking['id'].toString()];
            }
            setSheetState(() {});
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(content: Text(appStrings.attendanceError(error))),
            );
          }
        }

        Future<void> removeAttendee(
          Map<String, dynamic> booking,
          String name,
        ) async {
          final confirmed = await showAppConfirmationDialog(
            context: sheetContext,
            title: appStrings.removeBooking,
            message: name,
            confirmLabel: appStrings.remove,
            cancelLabel: appStrings.cancel,
          );
          if (!confirmed) return;
          try {
            await removeClassBookingAsAdmin(
              client: client,
              bookingId: booking['id'].toString(),
            );
            bookingRows.removeWhere((row) => row['id'] == booking['id']);
            setSheetState(() {});
            await attendeeActions?.onChanged?.call();
          } catch (error) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(content: Text(appStrings.attendanceError(error))),
            );
          }
        }

        return SizedBox.expand(
          child: ClassDetailsView(
            klass: klass,
            bookings: bookingRows,
            waitlist: waitlistRows,
            profilesById: profileById,
            myWaitlistPosition: myWaitlistPosition,
            actionLabel: actionLabel,
            adminActions: adminActions,
            attendeeActions: attendeeActions == null
                ? null
                : ClassDetailAttendeeActions(
                    onAddMember: (_) async {
                      await addMember();
                      return null;
                    },
                    onAddGuest: (_) async {
                      await addGuest();
                      return null;
                    },
                    onChanged: attendeeActions.onChanged,
                    canMarkAttendance: attendeeActions.canMarkAttendance,
                  ),
            onMemberTap: onMemberTap == null
                ? null
                : (memberId) {
                    Navigator.pop(sheetContext);
                    onMemberTap(memberId);
                  },
            intelligence: intelligence,
            pinnedNotesByMember: pinnedNotesByMember,
            onMarkAllAttended:
                operationsRepository != null && intelligence != null
                ? markAllAttended
                : null,
            onAttendeeStatusChanged: updateAttendeeStatus,
            onAttendeeRemoved: removeAttendee,
            onAction: onAction == null
                ? null
                : () {
                    Navigator.pop(sheetContext);
                    onAction();
                  },
            onBack: () => Navigator.pop(sheetContext),
          ),
        );
      },
    ),
  );
}

class ClassDetailsView extends StatelessWidget {
  const ClassDetailsView({
    super.key,
    required this.klass,
    required this.bookings,
    required this.waitlist,
    required this.profilesById,
    required this.actionLabel,
    required this.onAction,
    required this.onBack,
    this.adminActions = const [],
    this.attendeeActions,
    this.myWaitlistPosition,
    this.onAttendeeStatusChanged,
    this.onAttendeeRemoved,
    this.onMemberTap,
    this.intelligence,
    this.pinnedNotesByMember = const {},
    this.onMarkAllAttended,
  });

  final Map<String, dynamic> klass;
  final List<Map<String, dynamic>> bookings;
  final List<Map<String, dynamic>> waitlist;
  final Map<String, Map<String, dynamic>> profilesById;
  final int? myWaitlistPosition;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onBack;
  final List<ClassDetailAdminAction> adminActions;
  final ClassDetailAttendeeActions? attendeeActions;
  final Future<void> Function(Map<String, dynamic>, String)?
  onAttendeeStatusChanged;
  final Future<void> Function(Map<String, dynamic>, String)? onAttendeeRemoved;
  final ValueChanged<String>? onMemberTap;
  final CoachBriefingClass? intelligence;
  final Map<String, String> pinnedNotesByMember;
  final Future<void> Function()? onMarkAllAttended;

  String _formatDate(DateTime date) {
    final locale = appStrings.isEs ? 'es' : 'en';
    return DateFormat('EEE, d MMMM', locale).format(date);
  }

  String _time(DateTime date) => appPreferencesController.formatTime(
    date,
    locale: appStrings.isEs ? 'es' : 'en',
  );

  @override
  Widget build(BuildContext context) {
    final startsAt = DateTime.parse(klass['starts_at'].toString()).toLocal();
    final enrichedByBookingId = {
      for (final athlete
          in intelligence?.booked ?? const <CoachBriefingAthlete>[])
        athlete.bookingId: athlete,
    };
    final storedTitle = klass['title']?.toString().trim().isNotEmpty == true
        ? klass['title'].toString().trim()
        : appStrings.classFallback;
    final program = klass['programs'];
    final programName = program is Map
        ? program['name']?.toString().trim()
        : null;
    final title = programName?.isNotEmpty == true ? programName! : storedTitle;
    final duration = klass['duration_minutes'] as int? ?? 60;
    final capacity = klass['capacity'] as int? ?? 0;
    final description = storedTitle == programName ? '' : storedTitle;
    final coach = klass['coach'];
    final coachMap = coach is Map ? Map<String, dynamic>.from(coach) : null;
    final coachId = klass['coach_id']?.toString();
    final coachProfile = coachId == null ? null : profilesById[coachId];
    final coachName =
        coachProfile?['full_name']?.toString().trim() ??
        coachMap?['full_name']?.toString().trim();
    final coachAvatar =
        coachProfile?['avatar_url']?.toString() ??
        coachMap?['avatar_url']?.toString();
    final temporalStatus = intelligence?.temporalStatusAt(DateTime.now());
    final statusLabel = switch (temporalStatus) {
      CoachClassTemporalStatus.upcoming => 'UPCOMING',
      CoachClassTemporalStatus.inProgress => 'IN PROGRESS',
      CoachClassTemporalStatus.completed => 'COMPLETED',
      null => null,
    };

    return Material(
      color: AppColors.background(context),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ClassDetailHeader(
            title: title,
            onBack: onBack,
            adminActions: adminActions,
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
                  appStrings.pick('Class', 'Clase'),
                  style: AppTypography.helper(context),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.md,
                  children: [
                    _ClassFact(
                      icon: Icons.schedule_rounded,
                      value: intelligence?.localStartTime.isNotEmpty == true
                          ? intelligence!.localStartTime
                          : _time(startsAt),
                    ),
                    _ClassFact(
                      icon: Icons.calendar_today_outlined,
                      value: _formatDate(startsAt),
                    ),
                    _ClassFact(
                      icon: Icons.timer_outlined,
                      value: '$duration MIN',
                    ),
                    if (statusLabel != null)
                      _ClassFact(
                        icon: Icons.timelapse_rounded,
                        value: statusLabel,
                      ),
                    if (intelligence != null)
                      _ClassFact(
                        icon: Icons.groups_outlined,
                        value:
                            '${intelligence!.booked.length} / ${intelligence!.capacity}',
                      ),
                    if (intelligence?.waitlist.isNotEmpty == true)
                      _ClassFact(
                        icon: Icons.hourglass_bottom_rounded,
                        value:
                            '${appStrings.waitlist} ${intelligence!.waitlist.length}',
                      ),
                  ],
                ),
                const _ClassDetailDivider(),
                _ClassSectionTitle(label: appStrings.coach),
                const SizedBox(height: AppSpacing.md),
                if (coachName != null && coachName.isNotEmpty)
                  ClassPersonRow(
                    key: const ValueKey('class-detail-coach'),
                    name: coachName,
                    avatarUrl: coachAvatar,
                    showDivider: false,
                    onTap: coachId == null || onMemberTap == null
                        ? null
                        : () => onMemberTap!(coachId),
                  )
                else
                  Text(
                    appStrings.pick('No coach assigned', 'Sin coach asignado'),
                    style: AppTypography.bodySecondary(context),
                  ),
                const _ClassDetailDivider(),
                _ClassSectionTitle(label: appStrings.classDescriptionLabel),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  intelligence?.workoutDescription?.trim().isNotEmpty == true
                      ? intelligence!.workoutDescription!
                      : description.isEmpty
                      ? appStrings.pick(
                          intelligence == null
                              ? 'No description added.'
                              : 'No WOD programmed.',
                          intelligence == null
                              ? 'No se añadió descripción.'
                              : 'No hay WOD programado.',
                        )
                      : description,
                  style: AppTypography.bodySecondary(context).copyWith(
                    color: description.isEmpty
                        ? AppColors.textSecondary(context)
                        : AppColors.textPrimary(context),
                  ),
                ),
                const _ClassDetailDivider(),
                _ClassAttendeesHeader(
                  label: appStrings.pick('Attendees', 'Asistentes'),
                  count: capacity > 0
                      ? appStrings.classOccupancySummary(
                          bookings.length,
                          capacity,
                        )
                      : bookings.length.toString(),
                  actions: attendeeActions,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (bookings.isEmpty)
                  _ClassEmptyLabel(label: appStrings.noBookingsYet)
                else
                  ...bookings.map((booking) {
                    final isGuest = booking['is_guest'] == true;
                    final userId = booking['user_id']?.toString();
                    final profile = userId == null
                        ? null
                        : profilesById[userId];
                    final rawName = isGuest
                        ? booking['guest_name']?.toString()
                        : profile?['full_name']?.toString();
                    final name = rawName == null || rawName.trim().isEmpty
                        ? appStrings.member
                        : rawName.trim();
                    final athlete =
                        enrichedByBookingId[booking['id']?.toString()];
                    return ClassPersonRow(
                      name: name,
                      avatarUrl: isGuest
                          ? null
                          : profile?['avatar_url']?.toString(),
                      status: _attendeeStatus(booking['status']?.toString()),
                      badges: athlete == null
                          ? const []
                          : _intelligenceBadges(athlete, DateTime.now()),
                      staffNote: athlete?.userId == null
                          ? null
                          : pinnedNotesByMember[athlete!.userId],
                      onTap: isGuest || userId == null || onMemberTap == null
                          ? null
                          : () => onMemberTap!(userId),
                      actionKey: ValueKey('class-attendee-${booking['id']}'),
                      onAction:
                          attendeeActions == null && onMarkAllAttended == null
                          ? null
                          : () => _showAttendeeActions(
                              context,
                              booking: booking,
                              name: name,
                            ),
                    );
                  }),
                if (onMarkAllAttended != null &&
                    temporalStatus != CoachClassTemporalStatus.upcoming &&
                    bookings.any(
                      (booking) =>
                          booking['is_guest'] != true &&
                          booking['status'] == 'booked',
                    )) ...[
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const ValueKey('class-detail-mark-all-attended'),
                      onPressed: onMarkAllAttended,
                      style: FilledButton.styleFrom(
                        backgroundColor: BookingColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.done_all_rounded),
                      label: Text(
                        appStrings.pick(
                          'MARK ALL ATTENDED',
                          'MARCAR TODOS PRESENTES',
                        ),
                      ),
                    ),
                  ),
                ],
                if (waitlist.isNotEmpty || myWaitlistPosition != null) ...[
                  const _ClassDetailDivider(),
                  _ClassSectionHeader(
                    label: appStrings.waitlist,
                    count: waitlist.length.toString(),
                  ),
                  if (myWaitlistPosition != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      appStrings.bookingWaitlistPosition(myWaitlistPosition!),
                      style: AppTypography.helper(
                        context,
                      ).copyWith(color: BookingColors.primary),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ...waitlist.asMap().entries.map((entry) {
                    final profile =
                        profilesById[entry.value['user_id'].toString()];
                    final rawName = profile?['full_name']?.toString();
                    return ClassPersonRow(
                      name: rawName == null || rawName.trim().isEmpty
                          ? appStrings.member
                          : rawName.trim(),
                      avatarUrl: profile?['avatar_url']?.toString(),
                      position: entry.key + 1,
                      onTap: profile == null || onMemberTap == null
                          ? null
                          : () =>
                                onMemberTap!(entry.value['user_id'].toString()),
                    );
                  }),
                ],
              ],
            ),
          ),
          if (onAction != null && actionLabel.trim().isNotEmpty)
            _ClassDetailBottomAction(label: actionLabel, onPressed: onAction),
        ],
      ),
    );
  }

  String _attendeeStatus(String? status) => switch (status) {
    'attended' => appStrings.attended,
    'no_show' => appStrings.noShow,
    _ => appStrings.bookingBooked,
  };

  List<String> _intelligenceBadges(CoachBriefingAthlete athlete, DateTime now) {
    final badges = <String>[];
    if (athlete.firstClass) badges.add('FIRST CLASS');
    if (athlete.hasLowCredits) {
      final credits = athlete.creditsRemaining!;
      badges.add('$credits ${credits == 1 ? 'CREDIT' : 'CREDITS'} LEFT');
    }
    if (athlete.membershipExpiresWithin(now, const Duration(days: 7))) {
      final remaining = athlete.membershipExpiresAt!.difference(now);
      final days = remaining.inHours <= 24
          ? 0
          : (remaining.inHours / 24).ceil();
      badges.add(days == 0 ? 'EXPIRES TODAY' : 'EXPIRES IN $days DAYS');
    }
    if (!athlete.isGuest && !athlete.membershipUsable) {
      badges.add('NO MEMBERSHIP');
    }
    return badges;
  }

  void _showAttendeeActions(
    BuildContext context, {
    required Map<String, dynamic> booking,
    required String name,
  }) {
    final status = booking['status']?.toString() ?? 'booked';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (sheetContext) => AppAdminActionSheet(
        accentColor: BookingColors.primary,
        onClose: () => Navigator.pop(sheetContext),
        actions: [
          if ((attendeeActions?.canMarkAttendance == true ||
                  onMarkAllAttended != null) &&
              status != 'attended')
            AppAdminAction(
              icon: Icons.check_circle_outline_rounded,
              label: appStrings.markAttendance,
              onTap: () => onAttendeeStatusChanged?.call(booking, 'attended'),
            ),
          if ((attendeeActions?.canMarkAttendance == true ||
                  onMarkAllAttended != null) &&
              status != 'no_show')
            AppAdminAction(
              icon: Icons.person_off_outlined,
              label: appStrings.markNoShow,
              onTap: () => onAttendeeStatusChanged?.call(booking, 'no_show'),
            ),
          if (attendeeActions != null)
            AppAdminAction(
              icon: Icons.person_remove_alt_1_outlined,
              label: appStrings.remove,
              destructive: true,
              onTap: () => onAttendeeRemoved?.call(booking, name),
            ),
        ],
      ),
    );
  }
}

class _ClassDetailHeader extends StatelessWidget {
  const _ClassDetailHeader({
    required this.title,
    required this.onBack,
    required this.adminActions,
  });

  final String title;
  final VoidCallback onBack;
  final List<ClassDetailAdminAction> adminActions;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('class-detail-header'),
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('class-detail-back'),
          constraints: const BoxConstraints.tightFor(
            width: kMinInteractiveDimension,
            height: kMinInteractiveDimension,
          ),
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary(context),
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          width: kMinInteractiveDimension,
          height: kMinInteractiveDimension,
          child: adminActions.isEmpty
              ? null
              : ClassDetailAdminButton(actions: adminActions),
        ),
      ],
    ),
  );
}

class ClassDetailAdminButton extends StatelessWidget {
  const ClassDetailAdminButton({super.key, required this.actions});

  final List<ClassDetailAdminAction> actions;

  @override
  Widget build(BuildContext context) => BookingOutlineIconButton(
    tooltip: appStrings.classOptions,
    icon: Icons.edit_outlined,
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      isScrollControlled: true,
      builder: (sheetContext) => ClassDetailAdminSheet(
        actions: actions,
        onClose: () => Navigator.pop(sheetContext),
      ),
    ),
  );
}

class BookingOutlineIconButton extends StatelessWidget {
  const BookingOutlineIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppOutlinedAdminButton(
    icon: icon,
    tooltip: tooltip,
    onPressed: onPressed,
    accentColor: BookingColors.primary,
  );
}

class ClassDetailAdminSheet extends StatelessWidget {
  const ClassDetailAdminSheet({
    super.key,
    required this.actions,
    required this.onClose,
  });

  final List<ClassDetailAdminAction> actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => AppAdminActionSheet(
    accentColor: BookingColors.primary,
    onClose: onClose,
    actions: [
      for (final action in actions)
        AppAdminAction(
          icon: action.icon,
          label: action.label,
          onTap: action.onTap,
          destructive: action.destructive,
        ),
    ],
  );
}

class _ClassFact extends StatelessWidget {
  const _ClassFact({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: AppColors.textSecondary(context)),
      const SizedBox(width: AppSpacing.xs),
      Text(
        value,
        style: AppTypography.body(
          context,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _ClassDetailDivider extends StatelessWidget {
  const _ClassDetailDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Divider(height: 1, color: AppColors.border(context)),
  );
}

class _ClassSectionTitle extends StatelessWidget {
  const _ClassSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: AppTypography.sectionTitle(context).copyWith(letterSpacing: 0.6),
  );
}

class _ClassAttendeesHeader extends StatelessWidget {
  const _ClassAttendeesHeader({
    required this.label,
    required this.count,
    required this.actions,
  });

  final String label;
  final String count;
  final ClassDetailAttendeeActions? actions;

  @override
  Widget build(BuildContext context) {
    final titleAndCount = Row(
      children: [
        Expanded(child: _ClassSectionTitle(label: label)),
        Text(
          count,
          textAlign: TextAlign.right,
          style: AppTypography.helper(context),
        ),
      ],
    );
    final attendeeActions = actions;
    if (attendeeActions == null) return titleAndCount;

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BookingOutlineIconButton(
          key: const ValueKey('class-detail-add-member'),
          icon: Icons.person_add_alt_1_rounded,
          tooltip: appStrings.addMember,
          onPressed: () => attendeeActions.onAddMember(0),
        ),
        BookingOutlineIconButton(
          key: const ValueKey('class-detail-add-guest'),
          icon: Icons.group_add_outlined,
          tooltip: appStrings.addGuest,
          onPressed: () => attendeeActions.onAddGuest(0),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 250) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleAndCount,
              const SizedBox(height: AppSpacing.xs),
              Align(alignment: Alignment.centerRight, child: buttons),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: titleAndCount),
            const SizedBox(width: AppSpacing.xs),
            buttons,
          ],
        );
      },
    );
  }
}

class _ClassSectionHeader extends StatelessWidget {
  const _ClassSectionHeader({required this.label, required this.count});

  final String label;
  final String count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _ClassSectionTitle(label: label)),
      Text(count, style: AppTypography.helper(context)),
    ],
  );
}

class ClassPersonRow extends StatelessWidget {
  const ClassPersonRow({
    super.key,
    required this.name,
    this.avatarUrl,
    this.position,
    this.showDivider = true,
    this.status,
    this.onAction,
    this.actionKey,
    this.onTap,
    this.badges = const [],
    this.staffNote,
  });

  final String name;
  final String? avatarUrl;
  final int? position;
  final bool showDivider;
  final String? status;
  final VoidCallback? onAction;
  final Key? actionKey;
  final VoidCallback? onTap;
  final List<String> badges;
  final String? staffNote;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.input),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        decoration: showDivider
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.border(context),
                    width: 0.6,
                  ),
                ),
              )
            : null,
        child: Row(
          children: [
            if (position != null) ...[
              SizedBox(
                width: 24,
                child: Text('$position', style: AppTypography.helper(context)),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            AppAvatar(
              name: name,
              avatarUrl: hasAvatar ? avatarUrl : null,
              size: 36,
              foregroundColor: BookingColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (status != null)
                    Text(status!, style: AppTypography.helper(context)),
                  if (badges.isNotEmpty || staffNote != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Wrap(
                      spacing: AppSpacing.xxs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        for (final badge in badges.take(3))
                          _ClassContextBadge(label: badge),
                        if (badges.length > 3)
                          _ClassContextBadge(label: '+${badges.length - 3}'),
                        if (staffNote != null)
                          _ClassContextBadge(
                            key: ValueKey('class-detail-note-$name'),
                            label: 'NOTE',
                            icon: Icons.flag_outlined,
                            onTap: () => _showStaffNote(context, staffNote!),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (onAction != null)
              IconButton(
                key: actionKey,
                tooltip: appStrings.memberOptions,
                onPressed: onAction,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 19,
                  color: BookingColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showStaffNote(BuildContext context, String note) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.screenX),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NOTE', style: AppTypography.sectionTitle(context)),
            const SizedBox(height: AppSpacing.sm),
            Text(note, style: AppTypography.body(context)),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _ClassContextBadge extends StatelessWidget {
  const _ClassContextBadge({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadii.pill),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppColors.primary),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppTypography.helper(
              context,
            ).copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _ClassEmptyLabel extends StatelessWidget {
  const _ClassEmptyLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Text(label, style: AppTypography.bodySecondary(context)),
  );
}

class _ClassDetailBottomAction extends StatelessWidget {
  const _ClassDetailBottomAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.background(context),
      border: Border(
        top: BorderSide(color: AppColors.border(context), width: 0.8),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.sm,
          AppSpacing.screenX,
          AppSpacing.sm,
        ),
        child: SizedBox(
          width: double.infinity,
          height: AppSizes.buttonHeight,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: BookingColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(label.toUpperCase()),
          ),
        ),
      ),
    ),
  );
}
