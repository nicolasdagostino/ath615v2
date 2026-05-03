import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/attendance_sheet.dart';
import '../widgets/booking_class_card.dart';
import '../widgets/booking_day_chips.dart';
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

  Future<void> _load() async {
    setState(() => _loading = true);

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
      if (role == 'athlete') {
        hasActiveMembership =
            await _client.rpc('has_active_membership') == true;
      }

      if (gymId == null) {
        if (!mounted) return;
        setState(() {
          _gymId = null;
          _role = role;
          _classes = [];
          _myBookedClassIds = {};
          _hasActiveMembership = hasActiveMembership;
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
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Booking load error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bookClass(Map<String, dynamic> klass) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    if (!_hasActiveMembership) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Active membership required')),
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
      ).showSnackBar(const SnackBar(content: Text('Class is full')));
      return;
    }

    setState(() {
      _myBookedClassIds.add(classId);
      klass['booked_count'] = bookedCount + 1;
    });

    try {
      await _client.from('class_bookings').insert({
        'class_id': classId,
        'user_id': user.id,
        'status': 'booked',
      });

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking confirmed')));
    } catch (e) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Book class error: $e')));
    }
  }

  Future<void> _cancelBooking(Map<String, dynamic> klass) async {
    if (!_canCancelClass(klass)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Too late to cancel')));
      return;
    }

    final classId = klass['id'].toString();
    final bookedCount = klass['booked_count'] as int? ?? 0;

    setState(() {
      _myBookedClassIds.remove(classId);
      klass['booked_count'] = bookedCount > 0 ? bookedCount - 1 : 0;
    });

    try {
      await _client.rpc('cancel_my_booking', params: {'p_class_id': classId});
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking cancelled')));
    } catch (e) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel booking error: $e')));
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
    if (status == 'no_show') return 'No show';
    if (status == 'attended') return 'Attended';
    if (status == 'booked') return 'Booked';
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
    final selectedLabel =
        '${_selectedDay.day.toString().padLeft(2, '0')}/${_selectedDay.month.toString().padLeft(2, '0')}';

    return Scaffold(
      floatingActionButton: _canCreateClass
          ? FloatingActionButton(
              onPressed: _showCreateClassSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Text(
                  'Booking',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          BookingDayChips(
            selectedDay: _selectedDay,
            onSelected: (day) {
              setState(() => _selectedDay = day);
              _load();
            },
          ),
          if (_role == 'athlete' && !_hasActiveMembership)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'Active membership required to book classes.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _classes.isEmpty
                ? Center(child: Text('No classes on $selectedLabel.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _classes.length,
                    itemBuilder: (context, index) {
                      final klass = _classes[index];
                      final id = klass['id'].toString();
                      final booked = _myBookedClassIds.contains(id);
                      final bookedCount = klass['booked_count'] as int? ?? 0;
                      final capacity = klass['capacity'] as int? ?? 0;
                      final full = bookedCount >= capacity;
                      final state = _classState(klass);

                      String buttonLabel;
                      VoidCallback? buttonAction;

                      if (state == 'in_progress') {
                        buttonLabel = 'Class in progress';
                        buttonAction = null;
                      } else if (state == 'finished') {
                        buttonLabel = 'Finished';
                        buttonAction = null;
                      } else if (!_hasActiveMembership) {
                        buttonLabel = 'Membership required';
                        buttonAction = null;
                      } else if (booked) {
                        if (_canCancelClass(klass)) {
                          buttonLabel = 'Cancel';
                          buttonAction = () => _cancelBooking(klass);
                        } else {
                          buttonLabel = 'Booked';
                          buttonAction = null;
                        }
                      } else if (full) {
                        buttonLabel = 'Full';
                        buttonAction = null;
                      } else {
                        buttonLabel = 'Book';
                        buttonAction = () => _bookClass(klass);
                      }

                      return BookingClassCard(
                        klass: klass,
                        bookedCount: bookedCount,
                        capacity: capacity,
                        buttonLabel: buttonLabel,
                        buttonAction: buttonAction,
                        canManageAttendance: _canManageAttendance,
                        onOpenAttendance: () => _openAttendanceSheet(klass),
                        onMorePressed: _canCreateClass
                            ? () => _deleteClassOptions(klass)
                            : null,
                        formatDateTime: _formatDateTime,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
