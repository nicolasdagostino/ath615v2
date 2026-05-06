import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/attendance_sheet.dart';
import '../widgets/booking_class_card.dart';
import '../widgets/booking_day_chips.dart';
import '../widgets/booking_empty_state.dart';
import '../widgets/booking_loading_state.dart';
import '../widgets/booking_header.dart';
import '../widgets/membership_status_card.dart';
import '../widgets/create_class_sheet.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const int _cancelMinutes = 60;
  bool _loading = true;
  String? _role;
  String? _gymId;
  bool _hasActiveMembership = false;
  int? _creditsRemaining;

  DateTime _selectedDay = DateTime.now();

  List<Map<String, dynamic>> _classes = [];
  Set<String> _myBookedClassIds = {};

  SupabaseClient get _client => Supabase.instance.client;

  bool get _canCreateClass => _role == 'admin' || _role == 'owner';
  bool get _canManageAttendance => _role == 'admin' || _role == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
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
          .select('role, gym_id')
          .eq('id', user.id)
          .single();

      final gymId = profile['gym_id'] as String?;
      final role = profile['role'] as String?;

      bool hasActiveMembership = true;
      int? creditsRemaining;

      if (role == 'athlete') {
        final memberships = await _client
            .from('member_memberships')
            .select('credits_remaining, expires_at')
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

        hasActiveMembership = membership != null;
        creditsRemaining = membership?['credits_remaining'] as int?;

        debugPrint(
          'BOOKING MEMBERSHIP DEBUG => membership=$membership credits=$creditsRemaining has=$hasActiveMembership',
        );
      }

      if (gymId == null) {
        if (!mounted) return;
        setState(() {
          _gymId = null;
          _role = role;
          _classes = [];
          _myBookedClassIds = {};
          _hasActiveMembership = hasActiveMembership;
          _creditsRemaining = creditsRemaining;
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
            'id, title, starts_at, duration_minutes, capacity, recurring_id, created_at',
          )
          .eq('gym_id', gymId)
          .gte('starts_at', dayStart.toUtc().toIso8601String())
          .lt('starts_at', dayEnd.toUtc().toIso8601String())
          .order('starts_at', ascending: true);

      final bookings = await _client
          .from('class_bookings')
          .select('class_id, status')
          .eq('user_id', user.id)
          .eq('status', 'booked');

      final bookedIds = List<Map<String, dynamic>>.from(
        bookings,
      ).map((b) => b['class_id'].toString()).toSet();

      final classRows = List<Map<String, dynamic>>.from(classes);

      for (final c in classRows) {
        final bookingCount = await _client
            .from('class_bookings')
            .select('id')
            .eq('class_id', c['id'])
            .neq('status', 'cancelled')
            .count(CountOption.exact);

        c['booked_count'] = bookingCount.count;
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _gymId = gymId;
        _classes = classRows;
        _myBookedClassIds = bookedIds;
        _hasActiveMembership = hasActiveMembership;
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

  Future<void> _bookClass(Map<String, dynamic> klass) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

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

    try {
      await _client.rpc(
        'book_class_with_membership',
        params: {'p_class_id': classId},
      );

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingConfirmed)));
    } catch (e) {
      await _load();
      if (!mounted) return;
      final message = e.toString().contains('No credits remaining')
          ? appStrings.bookingNoCreditsRemaining
          : appStrings.bookingGenericError;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
      _myBookedClassIds.remove(classId);
      klass['booked_count'] = bookedCount > 0 ? bookedCount - 1 : 0;
      if (_role == 'athlete' && _creditsRemaining != null) {
        _creditsRemaining = _creditsRemaining! + 1;
      }
    });

    try {
      await _client.rpc('cancel_my_booking', params: {'p_class_id': classId});
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingCancelled)));
    } catch (e) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.bookingCancelError(e))));
    }
  }

  Future<void> _refresh() async {
    await _load(showLoading: false);
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

  Future<void> _deleteClassOptions(Map<String, dynamic> klass) async {
    final recurringId = klass['recurring_id'];
    final startsAt = klass['starts_at'];

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Delete this class'),
              onTap: () async {
                Navigator.pop(context);
                await _client.from('classes').delete().eq('id', klass['id']);
                _load();
              },
            ),
            if (recurringId != null)
              ListTile(
                title: const Text('Delete this + future'),
                onTap: () async {
                  Navigator.pop(context);
                  await _client
                      .from('classes')
                      .delete()
                      .eq('recurring_id', recurringId)
                      .gte('starts_at', startsAt);
                  _load();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttendanceSheet(Map<String, dynamic> klass) async {
    if (!_canManageAttendance) return;

    await showAttendanceSheet(
      context: context,
      client: _client,
      klass: klass,
      formatDateTime: _formatDateTime,
      prettyStatus: _prettyStatus,
      onChanged: _load,
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
    return Scaffold(
      floatingActionButton: _canCreateClass
          ? FloatingActionButton(
              heroTag: 'create-class',
              backgroundColor: const Color(0xFFB59B6A),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              onPressed: _showCreateClassSheet,
              child: const Icon(Icons.add),
            )
          : null,
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Column(
          children: [
            BookingHeader(selectedDay: _selectedDay, onRefresh: _refresh),
            BookingDayChips(
              selectedDay: _selectedDay,
              onSelected: (day) {
                setState(() => _selectedDay = day);
                _load();
              },
            ),
            if (_role == 'athlete')
              MembershipStatusCard(
                hasActiveMembership: _hasActiveMembership,
                creditsRemaining: _creditsRemaining,
              ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFB59B6A),
                onRefresh: _refresh,
                child: _loading
                    ? const BookingLoadingState()
                    : _classes.isEmpty
                    ? const BookingEmptyState()
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: _classes.length,
                        itemBuilder: (context, index) {
                          final klass = _classes[index];
                          final id = klass['id'].toString();
                          final booked = _myBookedClassIds.contains(id);
                          final bookedCount =
                              klass['booked_count'] as int? ?? 0;
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
                            if (_canCancelClass(klass)) {
                              buttonLabel = appStrings.bookingCancel;
                              buttonAction = () => _cancelBooking(klass);
                            } else {
                              buttonLabel = appStrings.bookingBooked;
                              buttonAction = null;
                            }
                          } else if (!_hasActiveMembership) {
                            buttonLabel = appStrings.bookingMembershipRequired;
                            buttonAction = null;
                          } else if (_role == 'athlete' &&
                              _creditsRemaining != null &&
                              _creditsRemaining! <= 0) {
                            buttonLabel = appStrings.bookingNoCreditsButton;
                            buttonAction = null;
                          } else if (full) {
                            buttonLabel = appStrings.bookingFull;
                            buttonAction = null;
                          } else {
                            buttonLabel = appStrings.bookingBook;
                            buttonAction = () => _bookClass(klass);
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
                              canManageAttendance: _canManageAttendance,
                              onOpenAttendance: () =>
                                  _openAttendanceSheet(klass),
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
      ),
    );
  }
}
