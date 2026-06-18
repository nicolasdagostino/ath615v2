import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_pickers.dart';

Future<void> showCreateClassSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
  required Future<void> Function() onCreated,
}) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) =>
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
        _selectedProgramId = null;
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
            'p_start_date':
                '${startsAt.year.toString().padLeft(4, '0')}-${startsAt.month.toString().padLeft(2, '0')}-${startsAt.day.toString().padLeft(2, '0')}',
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

      FocusScope.of(context).unfocus();

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
    return Scaffold(
      backgroundColor: const Color(0xFF252525),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF171717),
              border: Border(
                bottom: BorderSide(color: Color(0xFF2A2A2A), width: 0.8),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 50,
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFFB59B6A),
                            size: 34,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          appStrings.createClassTitle.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _ClassSheetText.title.copyWith(
                            color: Colors.white,
                            fontSize: 24,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                22,
                12,
                22,
                110 + MediaQuery.of(context).viewInsets.bottom,
              ),
              children: [
                if (_loadingPrograms)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFB59B6A),
                      ),
                    ),
                  )
                else if (_programs.isEmpty)
                  Text(appStrings.classNeedProgram, style: _ClassSheetText.body)
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedProgramId,
                    dropdownColor: const Color(0xFF171717),
                    iconEnabledColor: const Color(0xFFABABAB),
                    style: _ClassSheetText.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    hint: Text(
                      appStrings.workoutProgram,
                      style: _ClassSheetText.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    decoration: _programDropdownInput(
                      appStrings.workoutProgram,
                      Icons.fitness_center_outlined,
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        enabled: false,
                        child: Text(
                          appStrings.workoutProgram,
                          style: _ClassSheetText.subtle.copyWith(
                            color: const Color(0xFFABABAB),
                          ),
                        ),
                      ),
                      ..._programs.map((program) {
                        return DropdownMenuItem<String>(
                          value: program['id'].toString(),
                          child: Text(
                            program['name']?.toString() ??
                                appStrings.workoutProgram,
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedProgramId = value),
                  ),
                const SizedBox(height: 12),
                _ClassSheetActionRow(
                  icon: Icons.calendar_month_outlined,
                  title: appStrings.workoutDate,
                  subtitle: _selectedDate == null
                      ? ''
                      : _formatDate(_selectedDate!),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 12),
                _ClassSheetActionRow(
                  icon: Icons.schedule_rounded,
                  title: appStrings.time,
                  subtitle: _selectedTime == null
                      ? ''
                      : _selectedTime!.format(context),
                  onTap: _pickTime,
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF171717),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF323232),
                      width: 1,
                    ),
                  ),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
                    activeThumbColor: const Color(0xFFB59B6A),
                    activeTrackColor: const Color(0xFF3A3325),
                    inactiveThumbColor: const Color(0xFFABABAB),
                    inactiveTrackColor: const Color(0xFF323232),
                    value: _repeatWeekly,
                    onChanged: (value) => setState(() => _repeatWeekly = value),
                    title: Text(
                      appStrings.repeatWeekly,
                      style: _ClassSheetText.rowTitle.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      appStrings.repeatWeeklyDescription,
                      style: _ClassSheetText.subtle.copyWith(
                        color: const Color(0xFFABABAB),
                      ),
                    ),
                  ),
                ),
                if (_repeatWeekly) ...[
                  const SizedBox(height: 12),
                  Text(
                    appStrings.repeatOn.toUpperCase(),
                    style: _ClassSheetText.section.copyWith(
                      color: const Color(0xFFB59B6A),
                    ),
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
                          backgroundColor: const Color(0xFF171717),
                          selectedColor: const Color(0xFFB59B6A),
                          side: const BorderSide(
                            color: Color(0xFF323232),
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          labelStyle: _ClassSheetText.body.copyWith(
                            color: _selectedDays.contains(index + 1)
                                ? const Color(0xFF111111)
                                : Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
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
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _duration,
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        keyboardType: TextInputType.number,
                        style: _ClassSheetText.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: _classSheetInput(
                          appStrings.durationMinutes,
                          Icons.timer_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _capacity,
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        keyboardType: TextInputType.number,
                        style: _ClassSheetText.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
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
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: _CreateClassButton(
                label: appStrings.createClassTitle,
                loading: _saving,
                enabled: _canCreate,
                onPressed: _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _programDropdownInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: null,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    prefixIcon: Icon(icon, color: const Color(0xFFB59B6A), size: 20),
    filled: true,
    fillColor: const Color(0xFF171717),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF323232), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFAF986C), width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF323232), width: 1),
    ),
  );
}

InputDecoration _classSheetInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: null,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    hintStyle: _ClassSheetText.subtle.copyWith(color: const Color(0xFFABABAB)),
    prefixIcon: Icon(icon, color: const Color(0xFFB59B6A), size: 20),
    filled: true,
    fillColor: const Color(0xFF171717),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF323232), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFAF986C), width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF323232), width: 1),
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
    color: Colors.white,
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABABAB),
    letterSpacing: 0.3,
    height: 1,
  );
}

class _CreateClassButton extends StatelessWidget {
  const _CreateClassButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;

    return SizedBox(
      height: 58,
      width: double.infinity,
      child: FilledButton(
        onPressed: active ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: active
              ? const Color(0xFFB59B6A)
              : const Color(0xFF343434),
          disabledBackgroundColor: const Color(0xFF343434),
          foregroundColor: active
              ? const Color(0xFF111111)
              : const Color(0xFF777777),
          disabledForegroundColor: const Color(0xFF777777),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label.toUpperCase(),
                style: GoogleFonts.barlowCondensed(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  height: 1,
                ),
              ),
      ),
    );
  }
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
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(10),
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
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: _ClassSheetText.subtle),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFABABAB)),
            ],
          ),
        ),
      ),
    );
  }
}
