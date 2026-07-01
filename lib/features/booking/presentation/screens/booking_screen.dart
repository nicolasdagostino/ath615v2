import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/attendance_sheet.dart';
import '../widgets/class_details_sheet.dart';
import '../widgets/booking_class_card.dart';
import '../widgets/booking_day_chips.dart';
import '../widgets/booking_loading_state.dart';
import '../widgets/booking_header.dart';
import '../widgets/membership_status_card.dart';
import '../widgets/create_class_sheet.dart';
import '../widgets/edit_class_sheet.dart';

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
  bool _loading = true;
  String? _role;
  String? _gymId;
  bool _hasActiveMembership = false;
  bool _isAccountActive = true;
  int? _creditsRemaining;
  String? _membershipName;
  DateTime? _membershipExpiresAt;

  DateTime _selectedDay = DateTime.now();

  List<Map<String, dynamic>> _classes = [];
  Set<String> _myBookedClassIds = {};
  Map<String, int> _myWaitlistPositions = {};
  Map<String, String> _myClassStatuses = {};
  String? _bookingActionClassId;
  RealtimeChannel? _bookingRealtimeChannel;

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
            _load(showLoading: false);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'class_waitlist',
          callback: (_) {
            if (!mounted) return;
            _load(showLoading: false);
          },
        )
        .subscribe();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _loading = true);
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
      DateTime? membershipExpiresAt;

      if (role == 'athlete') {
        final memberships = await _client
            .from('member_memberships')
            .select('''
credits_remaining,
expires_at,
membership_plans(name)
''')
            .eq('user_id', user.id)
            .eq('is_active', true)
            .eq('status', 'active')
            .order('created_at', ascending: false);

        final now = DateTime.now();
        final activeMemberships = List<Map<String, dynamic>>.from(memberships)
            .where((membership) {
              final rawExpiresAt = membership['expires_at']?.toString();
              if (rawExpiresAt == null || rawExpiresAt.isEmpty) return true;
              final expiresAt = DateTime.tryParse(rawExpiresAt)?.toLocal();
              return expiresAt != null && expiresAt.isAfter(now);
            })
            .toList();

        final membership = activeMemberships.isEmpty
            ? null
            : activeMemberships.first;

        creditsRemaining = membership?['credits_remaining'] as int?;

        final plan = membership?['membership_plans'];
        if (plan is Map) {
          membershipName = plan['name']?.toString();
        } else if (plan is List && plan.isNotEmpty && plan.first is Map) {
          membershipName = (plan.first as Map)['name']?.toString();
        }

        final rawExpires = membership?['expires_at']?.toString();
        membershipExpiresAt = rawExpires == null
            ? null
            : DateTime.tryParse(rawExpires)?.toLocal();

        hasActiveMembership =
            membership != null &&
            (creditsRemaining == null || creditsRemaining > 0);

        debugPrint(
          'BOOKING MEMBERSHIP DEBUG => name=$membershipName membership=$membership credits=$creditsRemaining has=$hasActiveMembership',
        );
      }

      if (gymId == null) {
        if (!mounted) return;
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
          _membershipName = membershipName;
          _membershipExpiresAt = membershipExpiresAt;
        });
        return;
      }

      final dayStart = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));

      final classes = await _client
          .from('classes')
          .select(
            'id, title, starts_at, duration_minutes, capacity, recurring_id, created_at, program_id, programs(name, image_url)',
          )
          .eq('gym_id', gymId)
          .gte('starts_at', dayStart.toUtc().toIso8601String())
          .lt('starts_at', dayEnd.toUtc().toIso8601String())
          .order('starts_at', ascending: true);

      final bookings = await _client
          .from('class_bookings')
          .select('class_id, status')
          .eq('user_id', user.id)
          .neq('status', 'cancelled');

      final waitlist = await _client
          .from('class_waitlist')
          .select('class_id, created_at')
          .eq('user_id', user.id);

      final bookingRows = List<Map<String, dynamic>>.from(bookings);
      final bookedIds = bookingRows
          .map((b) => b['class_id'].toString())
          .toSet();
      final waitlistRows = List<Map<String, dynamic>>.from(waitlist);
      final waitlistPositions = <String, int>{};
      final bookingStatuses = {
        for (final b in bookingRows)
          b['class_id'].toString(): b['status'].toString(),
      };

      final classRows = List<Map<String, dynamic>>.from(classes);

      for (final c in classRows) {
        final bookingCount = await _client
            .from('class_bookings')
            .select('id')
            .eq('class_id', c['id'])
            .neq('status', 'cancelled')
            .count(CountOption.exact);

        c['booked_count'] = bookingCount.count;

        final classId = c['id'].toString();
        if (waitlistRows.any((w) => w['class_id'].toString() == classId)) {
          final classWaitlist = await _client
              .from('class_waitlist')
              .select('user_id')
              .eq('class_id', classId)
              .order('created_at', ascending: true);

          final classWaitlistRows = List<Map<String, dynamic>>.from(
            classWaitlist,
          );
          final index = classWaitlistRows.indexWhere(
            (w) => w['user_id']?.toString() == user.id,
          );

          if (index >= 0) {
            waitlistPositions[classId] = index + 1;
          }
        }
      }

      if (!mounted) return;
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
        _membershipName = membershipName;
        _membershipExpiresAt = membershipExpiresAt;
        _creditsRemaining = creditsRemaining;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingLoadError(e))));
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: EdgeInsets.all(AppSpacing.sheetMargin),
              padding: EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(AppRadii.sheet),
                border: Border.all(color: AppColors.border(context), width: 1),
                boxShadow: AppShadows.card(context),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.danger,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: _BookingSheetText.title.copyWith(
                            color: AppColors.textPrimary(context),
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: _BookingSheetText.body.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _BookingSheetSecondaryButton(
                          label: appStrings.cancel,
                          onTap: () => Navigator.pop(context, false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BookingSheetDangerButton(
                          label: appStrings.delete,
                          onTap: () => Navigator.pop(context, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _deleteClassOptions(Map<String, dynamic> klass) async {
    final recurringId = klass['recurring_id'];
    final startsAt = klass['starts_at'];
    final title = klass['title']?.toString() ?? appStrings.classFallback;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: EdgeInsets.all(AppSpacing.sheetMargin),
              padding: EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(AppRadii.sheet),
                border: Border.all(color: AppColors.border(context), width: 1),
                boxShadow: AppShadows.card(context),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.classOptions.toUpperCase(),
                    style: _BookingSheetText.title.copyWith(
                      color: AppColors.textPrimary(context),
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BookingSheetActionRow(
                    icon: Icons.edit_outlined,
                    title: appStrings.editClass,
                    subtitle: title,
                    onTap: () async {
                      Navigator.pop(context);
                      await _showEditClassSheet(klass);
                    },
                  ),
                  const SizedBox(height: 12),
                  _BookingSheetActionRow(
                    icon: Icons.delete_outline_rounded,
                    title: appStrings.deleteThisClass,
                    subtitle: title,
                    danger: true,
                    onTap: () async {
                      Navigator.pop(context);

                      final confirmed = await _confirmDeleteClass(
                        title: appStrings.deleteClassTitle,
                        message: appStrings.deleteOnlyThisClassMessage,
                      );

                      if (!confirmed) return;

                      await _client
                          .from('classes')
                          .delete()
                          .eq('id', klass['id']);
                      await _load(showLoading: false);
                    },
                  ),
                  if (recurringId != null) ...[
                    const SizedBox(height: 12),
                    _BookingSheetActionRow(
                      icon: Icons.delete_sweep_outlined,
                      title: appStrings.deleteThisAndFuture,
                      subtitle: appStrings.deleteThisAndFutureSubtitle,
                      danger: true,
                      onTap: () async {
                        Navigator.pop(context);

                        final confirmed = await _confirmDeleteClass(
                          title: appStrings.deleteFutureClassesTitle,
                          message: appStrings.deleteThisAndFutureMessage,
                        );

                        if (!confirmed) return;

                        await _client
                            .from('classes')
                            .delete()
                            .eq('recurring_id', recurringId)
                            .gte('starts_at', startsAt);
                        await _load(showLoading: false);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openClassSheet(Map<String, dynamic> klass) async {
    if (_canManageAttendance) {
      await showAttendanceSheet(
        context: context,
        client: _client,
        klass: klass,
        formatDateTime: _formatDateTime,
        prettyStatus: _prettyStatus,
        canMarkAttendance: _classState(klass) != 'upcoming',
        onChanged: _load,
      );
      return;
    }

    await showClassDetailsSheet(
      context: context,
      client: _client,
      klass: klass,
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

  String _prettyStatus(String status) {
    if (status == 'no_show') return appStrings.noShow;
    if (status == 'attended') return appStrings.attended;
    if (status == 'booked') return appStrings.bookingBooked;
    return status;
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
        statusBarColor: AppColors.surfaceAlt(context),
        statusBarIconBrightness: AppColors.isDark(context)
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: AppColors.isDark(context)
            ? Brightness.dark
            : Brightness.light,
      ),
    );

    return Scaffold(
      floatingActionButton: _canCreateClass
          ? FloatingActionButton(
              heroTag: 'create-class',
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              onPressed: _showCreateClassSheet,
              child: const Icon(Icons.add),
            )
          : null,
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          Container(
            color: AppColors.surfaceAlt(context),
            child: Column(
              children: [
                BookingHeader(
                  gymName: widget.gymName,
                  selectedDay: _selectedDay,
                  unreadNotifications: widget.unreadNotifications,
                  onOpenNotifications: widget.onOpenNotifications,
                ),
                const SizedBox(height: 0),
                BookingDayChips(
                  selectedDay: _selectedDay,
                  canViewPastDays: _canManageAttendance,
                  onSelected: (day) {
                    setState(() => _selectedDay = day);
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_role == 'athlete')
            MembershipStatusCard(
              hasActiveMembership: _hasActiveMembership,
              creditsRemaining: _creditsRemaining,
              planName: _membershipName,
              expiresAt: _membershipExpiresAt,
            ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accent,
              onRefresh: _refresh,
              child: _loading
                  ? const BookingLoadingState()
                  : _classes.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(28, 115, 28, 24),
                      children: const [_BookingRestDayEmptyState()],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
                            onTap: () => _openClassSheet(klass),
                            onMorePressed: _canCreateClass
                                ? () => _deleteClassOptions(klass)
                                : null,
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

class _BookingRestDayEmptyState extends StatelessWidget {
  const _BookingRestDayEmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          appStrings.restDayTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlowCondensed(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary(context),
            letterSpacing: -0.3,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          appStrings.restDayMessage,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary(context),
            letterSpacing: 0.3,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _BookingSheetText {
  const _BookingSheetText._();

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

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF666666),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF666666),
    letterSpacing: 0.3,
    height: 1,
  );
}

class _BookingSheetActionRow extends StatelessWidget {
  const _BookingSheetActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.accent;

    return Material(
      color: AppColors.surfaceAlt(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _BookingSheetText.rowTitle.copyWith(
                        color: danger
                            ? AppColors.danger
                            : AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: _BookingSheetText.subtle.copyWith(
                        color: AppColors.textSecondary(context),
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
      ),
    );
  }
}

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
