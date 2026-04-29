import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  bool _loading = true;
  String? _role;
  String? _gymId;
  bool _hasActiveMembership = false;

  DateTime _selectedDay = DateTime.now();

  List<Map<String, dynamic>> _classes = [];
  Set<String> _myBookedClassIds = {};

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canCreateClass => _role == 'admin' || _role == 'owner';
  bool get _canManageAttendance => _role == 'admin' || _role == 'owner';

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
            'id, title, starts_at, duration_minutes, capacity, created_at',
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
    } catch (e) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Book class error: $e')));
    }
  }

  Future<void> _cancelBooking(Map<String, dynamic> klass) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final classId = klass['id'].toString();
    final bookedCount = klass['booked_count'] as int? ?? 0;

    setState(() {
      _myBookedClassIds.remove(classId);
      klass['booked_count'] = bookedCount > 0 ? bookedCount - 1 : 0;
    });

    try {
      await _client.rpc('cancel_my_booking', params: {'p_class_id': classId});

      await _load();
    } catch (e) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel booking error: $e')));
    }
  }

  Future<void> _showCreateClassSheet() async {
    final title = TextEditingController(text: 'CrossFit');
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    final duration = TextEditingController(text: '60');
    final capacity = TextEditingController(text: '12');
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedStartsAt =
                selectedDate == null || selectedTime == null
                ? null
                : DateTime(
                    selectedDate!.year,
                    selectedDate!.month,
                    selectedDate!.day,
                    selectedTime!.hour,
                    selectedTime!.minute,
                  );

            final isPastClass =
                selectedStartsAt != null &&
                !selectedStartsAt.isAfter(DateTime.now());

            final canCreate =
                selectedStartsAt != null && !isPastClass && !saving;

            Future<void> save() async {
              if (_gymId == null) return;

              setSheetState(() => saving = true);

              try {
                if (selectedStartsAt == null) {
                  throw Exception('Select date and time');
                }

                if (!selectedStartsAt.isAfter(DateTime.now())) {
                  throw Exception('Class date and time must be in the future');
                }

                await _client.from('classes').insert({
                  'gym_id': _gymId,
                  'title': title.text.trim().isEmpty
                      ? 'Class'
                      : title.text.trim(),
                  'starts_at': selectedStartsAt.toUtc().toIso8601String(),
                  'duration_minutes': int.tryParse(duration.text.trim()) ?? 60,
                  'capacity': int.tryParse(capacity.text.trim()) ?? 12,
                  'created_by': _client.auth.currentUser?.id,
                });

                if (!mounted) return;
                Navigator.of(sheetContext).pop();
                await _load();
              } catch (e) {
                if (!sheetContext.mounted) return;

                await showDialog<void>(
                  context: sheetContext,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: const Text('Error'),
                      content: Text(
                        e.toString().replaceFirst('Exception: ', ''),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    );
                  },
                );
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  top: 8,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const Text(
                      'Create class',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(
                        selectedDate == null
                            ? 'Select date'
                            : '${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}',
                      ),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Time'),
                      subtitle: Text(
                        selectedTime == null
                            ? 'Select time'
                            : selectedTime!.format(context),
                      ),
                      trailing: const Icon(Icons.schedule),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedTime = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: duration,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duration minutes',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: capacity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Capacity'),
                    ),
                    if (isPastClass) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Choose a future date and time.',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    AppButton(
                      label: 'Create class',
                      loading: saving,
                      onPressed: canCreate ? save : null,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAttendanceSheet(Map<String, dynamic> klass) async {
    if (!_canManageAttendance) return;

    final classId = klass['id'].toString();

    final bookings = await _client
        .from('class_bookings')
        .select('id, user_id, status, created_at')
        .eq('class_id', classId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: true);

    final bookingRows = List<Map<String, dynamic>>.from(bookings);
    final userIds = bookingRows.map((b) => b['user_id'].toString()).toList();

    final profiles = userIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _client
                .from('profiles')
                .select('id, full_name, email')
                .inFilter('id', userIds),
          );

    final profileById = {for (final p in profiles) p['id'].toString(): p};

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> updateStatus(
              Map<String, dynamic> booking,
              String status,
            ) async {
              try {
                await _client
                    .from('class_bookings')
                    .update({'status': status})
                    .eq('id', booking['id']);

                booking['status'] = status;
                setSheetState(() {});
                await _load();
              } catch (e) {
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(
                  sheetContext,
                ).showSnackBar(SnackBar(content: Text('Attendance error: $e')));
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  top: 8,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      klass['title']?.toString() ?? 'Class',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_formatDateTime(klass['starts_at'])),
                    const SizedBox(height: 22),
                    const Text(
                      'Attendance',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (bookingRows.isEmpty)
                      const Text('No bookings yet.')
                    else
                      ...bookingRows.map((booking) {
                        final profile =
                            profileById[booking['user_id'].toString()];
                        final name =
                            (profile?['full_name'] ??
                                    profile?['email'] ??
                                    'Member')
                                .toString();
                        final email = (profile?['email'] ?? '').toString();
                        final status = booking['status'].toString();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (email.isNotEmpty) Text(email),
                                const SizedBox(height: 8),
                                Text('Status: ${_prettyStatus(status)}'),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            updateStatus(booking, 'attended'),
                                        child: const Text('Attended'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            updateStatus(booking, 'no_show'),
                                        child: const Text('No show'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          },
        );
      },
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

  String _weekdayLabel(DateTime day) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[day.weekday - 1];
  }

  Widget _buildDayChips() {
    final today = DateTime.now();

    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 14,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = DateTime(
            today.year,
            today.month,
            today.day,
          ).add(Duration(days: index));
          final selected =
              day.year == _selectedDay.year &&
              day.month == _selectedDay.month &&
              day.day == _selectedDay.day;

          return ChoiceChip(
            selected: selected,
            onSelected: (_) {
              setState(() => _selectedDay = day);
              _load();
            },
            label: SizedBox(
              width: 54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _weekdayLabel(day),
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    day.day.toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel =
        '${_selectedDay.day.toString().padLeft(2, '0')}/${_selectedDay.month.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: _canCreateClass
          ? FloatingActionButton(
              onPressed: _showCreateClassSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          _buildDayChips(),
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
                        buttonLabel = 'Cancel';
                        buttonAction = () => _cancelBooking(klass);
                      } else if (full) {
                        buttonLabel = 'Full';
                        buttonAction = null;
                      } else {
                        buttonLabel = 'Book';
                        buttonAction = () => _bookClass(klass);
                      }

                      final canTapButton = buttonAction != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: _canManageAttendance
                              ? () => _openAttendanceSheet(klass)
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  klass['title']?.toString() ?? 'Class',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(_formatDateTime(klass['starts_at'])),
                                const SizedBox(height: 6),
                                Text(
                                  '$bookedCount/$capacity spots · ${klass['duration_minutes'] ?? 60} min',
                                ),
                                if (_canManageAttendance) ...[
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Tap card to manage attendance',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: canTapButton
                                        ? buttonAction
                                        : null,
                                    child: Text(buttonLabel),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
