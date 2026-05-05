import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';

Future<void> showCreateClassSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
  required Future<void> Function() onCreated,
}) async {
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) =>
        _CreateClassSheet(client: client, gymId: gymId, onCreated: onCreated),
  );
}

class _CreateClassSheet extends StatefulWidget {
  const _CreateClassSheet({
    required this.client,
    required this.gymId,
    required this.onCreated,
  });

  final SupabaseClient client;
  final String gymId;
  final Future<void> Function() onCreated;

  @override
  State<_CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends State<_CreateClassSheet> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _duration = TextEditingController(text: '60');
  final _capacity = TextEditingController(text: '12');

  bool _loadingPrograms = true;
  bool _saving = false;
  bool _repeatWeekly = false;
  final List<int> _selectedDays = [];
  List<Map<String, dynamic>> _programs = [];
  String? _selectedProgramId;

  @override
  void initState() {
    super.initState();
    _loadPrograms();
  }

  @override
  void dispose() {
    _duration.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _loadPrograms() async {
    setState(() => _loadingPrograms = true);
    try {
      final rows = await widget.client
          .from('programs')
          .select('id, name')
          .eq('gym_id', widget.gymId)
          .eq('is_active', true)
          .order('name');

      final programs = List<Map<String, dynamic>>.from(rows);

      if (!mounted) return;
      setState(() {
        _programs = programs;
        _selectedProgramId = programs.isEmpty
            ? null
            : programs.first['id'].toString();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Programs load error: $e')));
    } finally {
      if (mounted) setState(() => _loadingPrograms = false);
    }
  }

  DateTime? get _selectedStartsAt {
    final date = _selectedDate;
    final time = _selectedTime;
    if (date == null || time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Map<String, dynamic>? get _selectedProgram {
    final id = _selectedProgramId;
    if (id == null) return null;

    for (final program in _programs) {
      if (program['id'].toString() == id) return program;
    }

    return null;
  }

  bool get _isPastClass {
    final startsAt = _selectedStartsAt;
    return startsAt != null && !startsAt.isAfter(DateTime.now());
  }

  bool get _canCreate {
    return !_loadingPrograms &&
        !_saving &&
        _selectedProgram != null &&
        _selectedStartsAt != null &&
        !_isPastClass;
  }

  Future<void> _save() async {
    if (!_canCreate) return;

    setState(() => _saving = true);

    try {
      final startsAt = _selectedStartsAt;
      final program = _selectedProgram;

      if (startsAt == null) throw Exception('Select date and time');
      if (program == null) throw Exception('Select a program');
      if (!startsAt.isAfter(DateTime.now())) {
        throw Exception('Class date and time must be in the future');
      }

      final programName = program['name']?.toString() ?? 'Class';
      final durationMinutes = int.tryParse(_duration.text.trim()) ?? 60;
      final capacity = int.tryParse(_capacity.text.trim()) ?? 12;

      if (_repeatWeekly && _selectedDays.isNotEmpty) {
        final time = TimeOfDay.fromDateTime(startsAt);

        await widget.client.rpc(
          'create_recurring_classes_multi',
          params: {
            'p_gym_id': widget.gymId,
            'p_program_id': program['id'],
            'p_title': programName,
            'p_time':
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00',
            'p_days': _selectedDays,
            'p_duration_minutes': durationMinutes,
            'p_capacity': capacity,
            'p_weeks': 8,
          },
        );
      } else if (_repeatWeekly) {
        await widget.client.rpc(
          'create_recurring_classes',
          params: {
            'p_gym_id': widget.gymId,
            'p_program_id': program['id'],
            'p_title': programName,
            'p_starts_at': startsAt.toUtc().toIso8601String(),
            'p_duration_minutes': durationMinutes,
            'p_capacity': capacity,
            'p_weeks': 8,
          },
        );
      } else {
        await widget.client.from('classes').insert({
          'gym_id': widget.gymId,
          'program_id': program['id'],
          'title': programName,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'duration_minutes': durationMinutes,
          'capacity': capacity,
          'created_by': widget.client.auth.currentUser?.id,
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onCreated();
    } catch (e) {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Error'),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked != null) setState(() => _selectedTime = picked);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
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
              appStrings.createClassTitle,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            if (_loadingPrograms)
              const Center(child: CircularProgressIndicator())
            else if (_programs.isEmpty)
              Text(
                appStrings.classNeedProgram,
                style: TextStyle(fontWeight: FontWeight.w700),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedProgramId,
                decoration: InputDecoration(
                  labelText: appStrings.workoutProgram,
                ),
                items: _programs.map((program) {
                  return DropdownMenuItem<String>(
                    value: program['id'].toString(),
                    child: Text(
                      program['name']?.toString() ?? appStrings.workoutProgram,
                    ),
                  );
                }).toList(),
                onChanged: (value) =>
                    setState(() => _selectedProgramId = value),
              ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(appStrings.workoutDate),
              subtitle: Text(
                _selectedDate == null
                    ? appStrings.selectDate
                    : _formatDate(_selectedDate!),
              ),
              trailing: const Icon(Icons.calendar_month),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(appStrings.time),
              subtitle: Text(
                _selectedTime == null
                    ? appStrings.selectTime
                    : _selectedTime!.format(context),
              ),
              trailing: const Icon(Icons.schedule),
              onTap: _pickTime,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _repeatWeekly,
              onChanged: (value) => setState(() => _repeatWeekly = value),
              title: Text(appStrings.repeatWeekly),
              subtitle: Text(appStrings.repeatWeeklyDescription),
            ),
            if (_repeatWeekly) ...[
              const SizedBox(height: 8),
              Text(
                appStrings.repeatOn,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final day in [
                    {'label': 'L', 'value': 1},
                    {'label': 'M', 'value': 2},
                    {'label': 'X', 'value': 3},
                    {'label': 'J', 'value': 4},
                    {'label': 'V', 'value': 5},
                    {'label': 'S', 'value': 6},
                    {'label': 'D', 'value': 7},
                  ])
                    ChoiceChip(
                      label: Text(day['label'] as String),
                      selected: _selectedDays.contains(day['value']),
                      onSelected: (selected) {
                        final value = day['value'] as int;
                        setState(() {
                          if (selected) {
                            _selectedDays.add(value);
                            _selectedDays.sort();
                          } else {
                            _selectedDays.remove(value);
                          }
                        });
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: appStrings.durationMinutes,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: appStrings.capacity),
            ),
            if (_isPastClass) ...[
              const SizedBox(height: 12),
              Text(
                appStrings.chooseFutureDateTime,
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 18),
            AppButton(
              label: appStrings.createClassTitle,
              loading: _saving,
              onPressed: _canCreate ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}
