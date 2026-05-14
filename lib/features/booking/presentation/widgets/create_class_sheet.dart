import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_pickers.dart';

Future<void> showCreateClassSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
  required Future<void> Function() onCreated,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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
      ).showSnackBar(SnackBar(content: Text(appStrings.programsLoadError(e))));
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

      if (startsAt == null) throw Exception(appStrings.selectDateTime);
      if (program == null) throw Exception(appStrings.selectProgram);
      if (!startsAt.isAfter(DateTime.now())) {
        throw Exception(appStrings.classFuture);
      }

      final programName =
          program['name']?.toString() ?? appStrings.classFallback;
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
            title: Text(appStrings.error),
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
    final picked = await showAppDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showAppTimePicker(
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                appStrings.createClassTitle.toUpperCase(),
                style: _ClassSheetText.title,
              ),
              const SizedBox(height: 18),
              if (_loadingPrograms)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFB59B6A)),
                  ),
                )
              else if (_programs.isEmpty)
                Text(appStrings.classNeedProgram, style: _ClassSheetText.body)
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedProgramId,
                  decoration: _classSheetInput(
                    appStrings.workoutProgram,
                    Icons.fitness_center_outlined,
                  ),
                  items: _programs.map((program) {
                    return DropdownMenuItem<String>(
                      value: program['id'].toString(),
                      child: Text(
                        program['name']?.toString() ??
                            appStrings.workoutProgram,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) =>
                      setState(() => _selectedProgramId = value),
                ),
              const SizedBox(height: 12),
              _ClassSheetActionRow(
                icon: Icons.calendar_month_outlined,
                title: appStrings.workoutDate,
                subtitle: _selectedDate == null
                    ? appStrings.selectDate
                    : _formatDate(_selectedDate!),
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),
              _ClassSheetActionRow(
                icon: Icons.schedule_rounded,
                title: appStrings.time,
                subtitle: _selectedTime == null
                    ? appStrings.selectTime
                    : _selectedTime!.format(context),
                onTap: _pickTime,
              ),
              const SizedBox(height: 12),
              Material(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(18),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                  activeThumbColor: const Color(0xFFB59B6A),
                  value: _repeatWeekly,
                  onChanged: (value) => setState(() => _repeatWeekly = value),
                  title: Text(
                    appStrings.repeatWeekly,
                    style: _ClassSheetText.rowTitle,
                  ),
                  subtitle: Text(
                    appStrings.repeatWeeklyDescription,
                    style: _ClassSheetText.subtle,
                  ),
                ),
              ),
              if (_repeatWeekly) ...[
                const SizedBox(height: 12),
                Text(
                  appStrings.repeatOn.toUpperCase(),
                  style: _ClassSheetText.section,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (
                      var index = 0;
                      index < appStrings.weekdayInitials.length;
                      index++
                    )
                      ChoiceChip(
                        label: Text(appStrings.weekdayInitials[index]),
                        selected: _selectedDays.contains(index + 1),
                        selectedColor: const Color(0xFFF7F3EA),
                        labelStyle: _ClassSheetText.body,
                        onSelected: (selected) {
                          final value = index + 1;
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      style: _ClassSheetText.body,
                      decoration: _classSheetInput(
                        appStrings.durationMinutes,
                        Icons.timer_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _capacity,
                      keyboardType: TextInputType.number,
                      style: _ClassSheetText.body,
                      decoration: _classSheetInput(
                        appStrings.capacity,
                        Icons.groups_outlined,
                      ),
                    ),
                  ),
                ],
              ),
              if (_isPastClass) ...[
                const SizedBox(height: 12),
                Text(
                  appStrings.chooseFutureDateTime,
                  style: _ClassSheetText.body.copyWith(
                    color: const Color(0xFFB42318),
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
      ),
    );
  }
}

InputDecoration _classSheetInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    hintStyle: _ClassSheetText.subtle,
    labelStyle: _ClassSheetText.subtle,
    prefixIcon: Icon(icon, color: const Color(0xFF8F96A3), size: 20),
    filled: true,
    fillColor: const Color(0xFFF4F5F7),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
  );
}

class _ClassSheetText {
  const _ClassSheetText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle section = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: 0.8,
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
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
    letterSpacing: 0.3,
    height: 1,
  );
}

class _ClassSheetActionRow extends StatelessWidget {
  const _ClassSheetActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFB59B6A), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _ClassSheetText.rowTitle),
                    const SizedBox(height: 4),
                    Text(subtitle, style: _ClassSheetText.subtle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF8F96A3)),
            ],
          ),
        ),
      ),
    );
  }
}
