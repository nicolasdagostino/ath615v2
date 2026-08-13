import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_async_state.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/attendance_add_booking_sheets.dart';
import '../widgets/class_details_sheet.dart';
import '../widgets/booking_class_card.dart';
import '../widgets/booking_create_class_button.dart';
import '../widgets/booking_day_chips.dart';
import '../widgets/booking_header.dart';
import '../widgets/create_class_sheet.dart';
import '../widgets/edit_class_sheet.dart';
import '../booking_colors.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({
    super.key,
    required this.gymName,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final String? gymName;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const int _cancelMinutes = 60;
  static const Duration _realtimeReloadDebounceDuration = Duration(
    milliseconds: 350,
  );
  bool _loading = true;
  String? _loadError;
  String? _role;
  String? _gymId;
  bool _hasActiveMembership = false;
  bool _isAccountActive = true;
  int? _creditsRemaining;

  DateTime _selectedDay = DateTime.now();

  List<Map<String, dynamic>> _classes = [];
  Set<String> _myBookedClassIds = {};
  Map<String, int> _myWaitlistPositions = {};
  Map<String, String> _myClassStatuses = {};
  String? _bookingActionClassId;
  RealtimeChannel? _bookingRealtimeChannel;
  Timer? _realtimeReloadDebounce;
  int _loadGeneration = 0;

  SupabaseClient get _client => Supabase.instance.client;

  bool get _canCreateClass => _role == 'admin' || _role == 'owner';
  bool get _canManageAttendance => _role == 'admin' || _role == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToBookingRealtime();
  }

  @override
  void dispose() {
    _realtimeReloadDebounce?.cancel();
    final channel = _bookingRealtimeChannel;
    if (channel != null) {
      _client.removeChannel(channel);
    }
    super.dispose();
  }

  void _subscribeToBookingRealtime() {
    _bookingRealtimeChannel = _client
        .channel('booking-screen-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'class_bookings',
          callback: (_) {
            if (!mounted) return;
            _scheduleRealtimeReload();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'class_waitlist',
          callback: (_) {
            if (!mounted) return;
            _scheduleRealtimeReload();
          },
        )
        .subscribe();
  }

  void _scheduleRealtimeReload() {
    if (!mounted) return;

    _realtimeReloadDebounce?.cancel();
    _realtimeReloadDebounce = Timer(_realtimeReloadDebounceDuration, () {
      _realtimeReloadDebounce = null;
      if (!mounted) return;
      _load(showLoading: false);
    });
  }

  Future<void> _load({bool showLoading = true}) async {
    if (!mounted) return;

    final requestedDay = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final loadGeneration = ++_loadGeneration;

    bool isCurrentLoad() {
      return mounted &&
          loadGeneration == _loadGeneration &&
          DateUtils.isSameDay(requestedDay, _selectedDay);
    }

    if (showLoading) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final profile = await _client
          .from('profiles')
          .select('role, gym_id, is_active')
          .eq('id', user.id)
          .single();

      final gymId = profile['gym_id'] as String?;
      final role = profile['role'] as String?;
      final isAccountActive = profile['is_active'] == true;

      bool hasActiveMembership = true;
      int? creditsRemaining;
      String? membershipName;

      if (role == 'athlete') {
        final result = await _client.rpc('get_current_usable_membership');

        final membershipRows = result is List
            ? List<Map<String, dynamic>>.from(result)
            : <Map<String, dynamic>>[];

        final membership = membershipRows.isEmpty ? null : membershipRows.first;

        creditsRemaining = membership?['credits_remaining'] as int?;
        membershipName = membership?['plan_name']?.toString();

        hasActiveMembership = membership != null;

        debugPrint(
          'BOOKING MEMBERSHIP DEBUG => '
          'name=$membershipName '
          'membership=$membership '
          'credits=$creditsRemaining '
          'has=$hasActiveMembership',
        );
      }

      if (gymId == null) {
        if (!isCurrentLoad()) return;
        setState(() {
          _gymId = null;
          _role = role;
          _classes = [];
          _myBookedClassIds = {};
          _myWaitlistPositions = {};
          _myClassStatuses = {};
          _hasActiveMembership = hasActiveMembership;
          _isAccountActive = isAccountActive;
          _creditsRemaining = creditsRemaining;
        });
        return;
      }

      final dayStart = requestedDay;
      final dayEnd = dayStart.add(const Duration(days: 1));

      final classes = await _client
          .from('classes')
          .select(
            'id, title, starts_at, duration_minutes, capacity, recurring_id, created_at, program_id, coach_id, programs(name, image_url), coach:profiles!classes_coach_id_fkey(full_name)',
          )
          .eq('gym_id', gymId)
          .gte('starts_at', dayStart.toUtc().toIso8601String())
          .lt('starts_at', dayEnd.toUtc().toIso8601String())
          .order('starts_at', ascending: true);

      final classRows = List<Map<String, dynamic>>.from(classes);
      final classIds = classRows.map((c) => c['id'].toString()).toList();
      var bookingRows = <Map<String, dynamic>>[];
      var waitlistRows = <Map<String, dynamic>>[];

      if (classIds.isNotEmpty) {
        final bookings = await _client
            .from('class_bookings')
            .select('class_id, user_id, status')
            .inFilter('class_id', classIds)
            .neq('status', 'cancelled');

        final waitlist = await _client
            .from('class_waitlist')
            .select('class_id, user_id, created_at')
            .inFilter('class_id', classIds)
            .order('class_id', ascending: true)
            .order('created_at', ascending: true);

        bookingRows = List<Map<String, dynamic>>.from(bookings);
        waitlistRows = List<Map<String, dynamic>>.from(waitlist);
      }

      final bookedCountByClass = <String, int>{};
      final bookedIds = <String>{};
      final bookingStatuses = <String, String>{};

      for (final booking in bookingRows) {
        final classId = booking['class_id']?.toString();
        if (classId == null) continue;

        bookedCountByClass[classId] = (bookedCountByClass[classId] ?? 0) + 1;

        if (booking['user_id']?.toString() == user.id) {
          bookedIds.add(classId);
          bookingStatuses[classId] = booking['status'].toString();
        }
      }

      final waitlistPositions = <String, int>{};
      final waitlistCountByClass = <String, int>{};

      for (final entry in waitlistRows) {
        final classId = entry['class_id']?.toString();
        if (classId == null) continue;

        final position = (waitlistCountByClass[classId] ?? 0) + 1;
        waitlistCountByClass[classId] = position;

        if (entry['user_id']?.toString() == user.id) {
          waitlistPositions[classId] = position;
        }
      }

      for (final c in classRows) {
        final classId = c['id'].toString();
        c['booked_count'] = bookedCountByClass[classId] ?? 0;
      }

      if (!isCurrentLoad()) return;
      setState(() {
        _role = role;
        _gymId = gymId;
        _classes = classRows;
        _myBookedClassIds = bookedIds;
        _myWaitlistPositions = waitlistPositions;
        _myClassStatuses = bookingStatuses;
        _hasActiveMembership = hasActiveMembership;
        _isAccountActive = isAccountActive;
        _creditsRemaining = creditsRemaining;
        _creditsRemaining = creditsRemaining;
        _loadError = null;
      });
    } catch (e) {
      if (!isCurrentLoad()) return;
      if (!mounted) return;
      setState(() => _loadError = appStrings.bookingLoadError(e));
    } finally {
      if (isCurrentLoad() && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _joinWaitlist(Map<String, dynamic> klass) async {
    final classId = klass['id'].toString();

    setState(() => _bookingActionClassId = classId);

    try {
      await _client.rpc('join_class_waitlist', params: {'p_class_id': classId});

      await _load(showLoading: false);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingWaitlistJoined)));
    } catch (e) {
      await _load(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingWaitlistError)));
    } finally {
      if (mounted) {
        setState(() => _bookingActionClassId = null);
      }
    }
  }

  Future<void> _leaveWaitlist(Map<String, dynamic> klass) async {
    final classId = klass['id'].toString();

    setState(() => _bookingActionClassId = classId);

    try {
      await _client.rpc(
        'leave_class_waitlist',
        params: {'p_class_id': classId},
      );

      await _load(showLoading: false);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingWaitlistLeft)));
    } catch (e) {
      await _load(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingWaitlistError)));
    } finally {
      if (mounted) {
        setState(() => _bookingActionClassId = null);
      }
    }
  }

  Future<void> _bookClass(Map<String, dynamic> klass) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    if (!_isAccountActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activate your account to reserve classes.'),
        ),
      );
      return;
    }

    if (!_hasActiveMembership) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.bookingActiveMembershipRequired)),
      );
      return;
    }

    final classId = klass['id'].toString();
    final capacity = klass['capacity'] as int? ?? 0;
    final bookedCount = klass['booked_count'] as int? ?? 0;

    if (_myBookedClassIds.contains(classId)) return;

    if (bookedCount >= capacity) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingClassFull)));
      return;
    }

    setState(() => _bookingActionClassId = classId);

    try {
      await _client.rpc(
        'book_class_with_membership',
        params: {'p_class_id': classId},
      );

      await _load(showLoading: false);

      if (!mounted) return;
    } catch (e) {
      await _load(showLoading: false);
      if (!mounted) return;
      final message = e.toString().contains('No credits remaining')
          ? appStrings.bookingNoCreditsRemaining
          : appStrings.bookingGenericError;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _bookingActionClassId = null);
      }
    }
  }

  Future<void> _cancelBooking(Map<String, dynamic> klass) async {
    if (!_canCancelClass(klass)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingTooLateCancel)));
      return;
    }

    final classId = klass['id'].toString();
    final bookedCount = klass['booked_count'] as int? ?? 0;

    setState(() {
      _bookingActionClassId = classId;
      _myBookedClassIds.remove(classId);
      klass['booked_count'] = bookedCount > 0 ? bookedCount - 1 : 0;
      if (_role == 'athlete' && _creditsRemaining != null) {
        _creditsRemaining = _creditsRemaining! + 1;
        _hasActiveMembership = true;
      }
    });

    try {
      await _client.rpc('cancel_my_booking', params: {'p_class_id': classId});
      await _sendPendingNotifications();
      await _load(showLoading: false);

      if (!mounted) return;
    } catch (e) {
      await _load(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingCancelError(e))));
    } finally {
      if (mounted) {
        setState(() => _bookingActionClassId = null);
      }
    }
  }

  Future<void> _refresh() async {
    await _load(showLoading: false);
  }

  Future<void> _sendPendingNotifications() async {
    try {
      await _client.functions.invoke('send-notifications');
    } catch (_) {
      // Notifications are still queued and will be sent by the scheduler.
    }
  }

  Future<void> _showCreateClassSheet() async {
    final gymId = _gymId;
    if (gymId == null) return;

    await showCreateClassSheet(
      context: context,
      client: _client,
      gymId: gymId,
      onCreated: _load,
    );
  }

  Future<void> _showEditClassSheet(Map<String, dynamic> klass) async {
    final gymId = _gymId;
    if (gymId == null) return;

    await showEditClassSheet(
      context: context,
      client: _client,
      gymId: gymId,
      klass: klass,
      onUpdated: _load,
    );
  }

  Future<bool> _confirmDeleteClass({
    required String title,
    required String message,
  }) async {
    return showAppConfirmationDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: appStrings.delete,
      cancelLabel: appStrings.cancel,
    );
  }

  Future<void> _deleteClass(Map<String, dynamic> klass) async {
    final confirmed = await _confirmDeleteClass(
      title: appStrings.deleteClassTitle,
      message: appStrings.deleteOnlyThisClassMessage,
    );
    if (!confirmed) return;

    await _client.from('classes').delete().eq('id', klass['id']);
    await _load(showLoading: false);
  }

  Future<void> _deleteFutureClasses(Map<String, dynamic> klass) async {
    final confirmed = await _confirmDeleteClass(
      title: appStrings.deleteFutureClassesTitle,
      message: appStrings.deleteThisAndFutureMessage,
    );
    if (!confirmed) return;

    await _client
        .from('classes')
        .delete()
        .eq('recurring_id', klass['recurring_id'])
        .gte('starts_at', klass['starts_at']);
    await _load(showLoading: false);
  }

  Future<void> _openClassSheet(
    Map<String, dynamic> klass, {
    required String actionLabel,
    required VoidCallback? action,
  }) async {
    await showClassDetailsSheet(
      context: context,
      client: _client,
      klass: klass,
      actionLabel: actionLabel,
      onAction: action,
      adminActions: _canManageAttendance
          ? [
              ClassDetailAdminAction(
                icon: Icons.edit_outlined,
                label: appStrings.editClass,
                onTap: () => _showEditClassSheet(klass),
              ),
              ClassDetailAdminAction(
                icon: Icons.delete_outline_rounded,
                label: appStrings.deleteThisClass,
                destructive: true,
                onTap: () => _deleteClass(klass),
              ),
              if (klass['recurring_id'] != null)
                ClassDetailAdminAction(
                  icon: Icons.delete_sweep_outlined,
                  label: appStrings.deleteThisAndFuture,
                  destructive: true,
                  onTap: () => _deleteFutureClasses(klass),
                ),
            ]
          : const [],
      attendeeActions: _canManageAttendance
          ? ClassDetailAttendeeActions(
              onAddMember: (bookingCount) async {
                final result = await showAttendanceAddMember(
                  context: context,
                  client: _client,
                  classId: klass['id'].toString(),
                  bookingCount: bookingCount,
                  capacity: klass['capacity'] as int? ?? 0,
                );
                if (result != null) await _load(showLoading: false);
                return result;
              },
              onAddGuest: (bookingCount) async {
                final result = await showAttendanceAddGuest(
                  context: context,
                  client: _client,
                  classId: klass['id'].toString(),
                  bookingCount: bookingCount,
                  capacity: klass['capacity'] as int? ?? 0,
                );
                if (result != null) await _load(showLoading: false);
                return result;
              },
              onChanged: () => _load(showLoading: false),
              canMarkAttendance: _classState(klass) != 'upcoming',
            )
          : null,
    );
  }

  String _classState(Map<String, dynamic> klass) {
    final startsAt = DateTime.parse(klass['starts_at']).toLocal();
    final durationMinutes = klass['duration_minutes'] as int? ?? 60;
    final endsAt = startsAt.add(Duration(minutes: durationMinutes));
    final now = DateTime.now();

    if (now.isBefore(startsAt)) return 'upcoming';
    if (now.isBefore(endsAt)) return 'in_progress';
    return 'finished';
  }

  bool _canCancelClass(Map<String, dynamic> klass) {
    final startsAt = DateTime.parse(klass['starts_at']).toLocal();
    final cancelLimit = startsAt.subtract(
      const Duration(minutes: _cancelMinutes),
    );

    return DateTime.now().isBefore(cancelLimit);
  }

  String _formatDateTime(String raw) {
    final dt = DateTime.parse(raw).toLocal();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m · $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: BookingColors.primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      floatingActionButton: _canCreateClass
          ? BookingCreateClassButton(onPressed: _showCreateClassSheet)
          : null,
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          Container(
            color: AppColors.background(context),
            child: Column(
              children: [
                BookingHeader(gymName: widget.gymName),
                const SizedBox(height: AppSpacing.md),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
                  child: BookingClassesChip(),
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenX,
                  ),
                  child: Divider(
                    height: 1,
                    thickness: 0.8,
                    color: AppColors.border(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                BookingDayChips(
                  selectedDay: _selectedDay,
                  canViewPastDays: _canManageAttendance,
                  onSelected: (day) {
                    setState(() => _selectedDay = day);
                    _load();
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                BookingSelectedDateLabel(selectedDay: _selectedDay),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: BookingColors.primary,
              onRefresh: _refresh,
              child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 180),
                        AppCenteredLoadingIndicator(
                          color: BookingColors.primary,
                        ),
                      ],
                    )
                  : _loadError != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        AppAsyncState.error(
                          message: _loadError!,
                          actionLabel: appStrings.retry,
                          onAction: _load,
                        ),
                      ],
                    )
                  : _classes.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        AppAsyncState.empty(
                          icon: Icons.event_busy_outlined,
                          message: appStrings.restDayMessage,
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.screenX,
                        0,
                        AppSpacing.screenX,
                        88,
                      ),
                      itemCount: _classes.length,
                      itemBuilder: (context, index) {
                        final klass = _classes[index];
                        final id = klass['id'].toString();
                        final myStatus = _myClassStatuses[id];
                        final booked = myStatus != null;
                        final waitlistPosition = _myWaitlistPositions[id];
                        final waitlisted = waitlistPosition != null;
                        final bookedCount = klass['booked_count'] as int? ?? 0;
                        final capacity = klass['capacity'] as int? ?? 0;
                        final full = bookedCount >= capacity;
                        final state = _classState(klass);

                        String buttonLabel;
                        VoidCallback? buttonAction;

                        if (state == 'in_progress') {
                          buttonLabel = appStrings.bookingInProgress;
                          buttonAction = null;
                        } else if (state == 'finished') {
                          buttonLabel = appStrings.bookingFinished;
                          buttonAction = null;
                        } else if (booked) {
                          if (state == 'upcoming') {
                            if (_canCancelClass(klass)) {
                              buttonLabel = appStrings.bookingCancel;
                              buttonAction = () => _cancelBooking(klass);
                            } else {
                              buttonLabel = appStrings.bookingBooked;
                              buttonAction = null;
                            }
                          } else if (myStatus == 'attended') {
                            buttonLabel = appStrings.attended;
                            buttonAction = null;
                          } else if (myStatus == 'no_show') {
                            buttonLabel = appStrings.noShow;
                            buttonAction = null;
                          } else {
                            buttonLabel = appStrings.bookingBooked;
                            buttonAction = null;
                          }
                        } else if (!_isAccountActive) {
                          buttonLabel = 'Activate account';
                          buttonAction = null;
                        } else if (!_hasActiveMembership) {
                          buttonLabel = appStrings.bookingMembershipRequired;
                          buttonAction = null;
                        } else if (_role == 'athlete' &&
                            _creditsRemaining != null &&
                            _creditsRemaining! <= 0) {
                          buttonLabel = appStrings.bookingNoCreditsButton;
                          buttonAction = null;
                        } else if (waitlisted) {
                          buttonLabel = appStrings.bookingLeaveWaitlist;
                          buttonAction = () => _leaveWaitlist(klass);
                        } else if (full) {
                          buttonLabel = appStrings.bookingJoinWaitlist;
                          buttonAction = () => _joinWaitlist(klass);
                        } else {
                          buttonLabel = appStrings.bookingBook;
                          buttonAction = () => _bookClass(klass);
                        }

                        final isProcessing = _bookingActionClassId == id;

                        if (isProcessing) {
                          buttonAction = null;
                        }

                        return TweenAnimationBuilder<double>(
                          key: ValueKey(
                            '${klass['id']}-${_selectedDay.toIso8601String()}',
                          ),
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(
                            milliseconds: 220 + (index * 35).clamp(0, 220),
                          ),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 18 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: BookingClassCard(
                            klass: klass,
                            bookedCount: bookedCount,
                            capacity: capacity,
                            buttonLabel: buttonLabel,
                            buttonAction: buttonAction,
                            isLoading: isProcessing,
                            waitlistPosition: waitlistPosition,
                            onTap: () => _openClassSheet(
                              klass,
                              actionLabel: buttonLabel,
                              action: buttonAction,
                            ),
                            formatDateTime: _formatDateTime,
                          ),
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

class _BookingSheetText {
  const _BookingSheetText._();

  // ignore: unused_field
  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle rowTitle = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.2,
    height: 1,
  );

  // ignore: unused_field
  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF666666),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );
}

// ignore: unused_element
class _BookingSheetSecondaryButton extends StatelessWidget {
  const _BookingSheetSecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary(context),
          side: BorderSide(color: AppColors.border(context)),
          backgroundColor: AppColors.surfaceAlt(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _BookingSheetText.rowTitle.copyWith(
            color: AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _BookingSheetDangerButton extends StatelessWidget {
  const _BookingSheetDangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _BookingSheetText.rowTitle.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
