import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';

Future<void> showEditClassSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
  required Map<String, dynamic> klass,
  required Future<void> Function() onUpdated,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditClassSheet(
      client: client,
      gymId: gymId,
      klass: klass,
      onUpdated: onUpdated,
    ),
  );
}

class _EditClassSheet extends StatefulWidget {
  const _EditClassSheet({
    required this.client,
    required this.gymId,
    required this.klass,
    required this.onUpdated,
  });

  final SupabaseClient client;
  final String gymId;
  final Map<String, dynamic> klass;
  final Future<void> Function() onUpdated;

  @override
  State<_EditClassSheet> createState() => _EditClassSheetState();
}

class _EditClassSheetState extends State<_EditClassSheet> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  late final TextEditingController _duration;
  late final TextEditingController _capacity;

  bool _loadingPrograms = true;
  bool _saving = false;
  List<Map<String, dynamic>> _programs = [];
  String? _selectedProgramId;

  @override
  void initState() {
    super.initState();

    final startsAt = DateTime.parse(widget.klass['starts_at']).toLocal();

    _selectedDate = DateTime(startsAt.year, startsAt.month, startsAt.day);
    _selectedTime = TimeOfDay.fromDateTime(startsAt);
    _duration = TextEditingController(
      text: (widget.klass['duration_minutes'] ?? 60).toString(),
    );
    _capacity = TextEditingController(
      text: (widget.klass['capacity'] ?? 12).toString(),
    );
    _selectedProgramId = widget.klass['program_id']?.toString();

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
        _selectedProgramId ??= programs.isEmpty
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

  bool get _canSave {
    return !_loadingPrograms &&
        !_saving &&
        _selectedProgram != null &&
        _selectedStartsAt != null;
  }

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() => _saving = true);

    try {
      final startsAt = _selectedStartsAt;
      final program = _selectedProgram;

      if (startsAt == null) throw Exception('Select date and time');
      if (program == null) throw Exception('Select a program');

      final programName = program['name']?.toString() ?? appStrings.classFallback;
      final durationMinutes = int.tryParse(_duration.text.trim()) ?? 60;
      final capacity = int.tryParse(_capacity.text.trim()) ?? 12;

      await widget.client.from('classes').update({
        'program_id': program['id'],
        'title': programName,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'duration_minutes': durationMinutes,
        'capacity': capacity,
      }).eq('id', widget.klass['id']);

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onUpdated();
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );

    if (picked != null) setState(() => _selectedTime = picked);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              Text('EDIT CLASS', style: _EditClassSheetText.title),
              const SizedBox(height: 18),
              if (_loadingPrograms)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFB59B6A)),
                  ),
                )
              else if (_programs.isEmpty)
                Text(appStrings.classNeedProgram, style: _EditClassSheetText.body)
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedProgramId,
                  decoration: _editClassInput(
                    appStrings.workoutProgram,
                    Icons.fitness_center_outlined,
                  ),
                  items: _programs.map((program) {
                    return DropdownMenuItem<String>(
                      value: program['id'].toString(),
                      child: Text(
                        program['name']?.toString() ?? appStrings.workoutProgram,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedProgramId = value),
                ),
              const SizedBox(height: 12),
              _EditClassActionRow(
                icon: Icons.calendar_month_outlined,
                title: appStrings.workoutDate,
                subtitle: _selectedDate == null
                    ? appStrings.selectDate
                    : _formatDate(_selectedDate!),
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),
              _EditClassActionRow(
                icon: Icons.schedule_rounded,
                title: appStrings.time,
                subtitle: _selectedTime == null
                    ? appStrings.selectTime
                    : _selectedTime!.format(context),
                onTap: _pickTime,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      style: _EditClassSheetText.body,
                      decoration: _editClassInput(
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
                      style: _EditClassSheetText.body,
                      decoration: _editClassInput(
                        appStrings.capacity,
                        Icons.groups_outlined,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AppButton(
                label: appStrings.workoutSaveChanges,
                loading: _saving,
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _editClassInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    hintStyle: _EditClassSheetText.subtle,
    labelStyle: _EditClassSheetText.subtle,
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

class _EditClassSheetText {
  const _EditClassSheetText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
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

class _EditClassActionRow extends StatelessWidget {
  const _EditClassActionRow({
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
                    Text(title, style: _EditClassSheetText.rowTitle),
                    const SizedBox(height: 4),
                    Text(subtitle, style: _EditClassSheetText.subtle),
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
