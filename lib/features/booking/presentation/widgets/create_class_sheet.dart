import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_pickers.dart';
import '../../data/class_coach_repository.dart';
import '../../domain/class_coach.dart';
import 'class_coach_selector.dart';

Future<void> showCreateClassSheet({
  required BuildContext context,
  SupabaseClient? client,
  required String gymId,
  required Future<void> Function() onCreated,
  ClassCoachRepository? coachRepository,
  Future<List<Map<String, dynamic>>> Function()? programsLoader,
}) async {
  assert(
    client != null || (coachRepository != null && programsLoader != null),
    'A Supabase client or injected option loaders are required.',
  );
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _CreateClassSheet(
      client: client,
      gymId: gymId,
      onCreated: onCreated,
      coachRepository: coachRepository,
      programsLoader: programsLoader,
    ),
  );
}

class _CreateClassSheet extends StatefulWidget {
  const _CreateClassSheet({
    required this.client,
    required this.gymId,
    required this.onCreated,
    this.coachRepository,
    this.programsLoader,
  });

  final SupabaseClient? client;
  final String gymId;
  final Future<void> Function() onCreated;
  final ClassCoachRepository? coachRepository;
  final Future<List<Map<String, dynamic>>> Function()? programsLoader;

  @override
  State<_CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends State<_CreateClassSheet> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _duration = TextEditingController(text: '60');
  final _capacity = TextEditingController(text: '12');

  bool _loadingPrograms = true;
  bool _loadingCoaches = true;
  bool _saving = false;
  bool _repeatWeekly = false;
  final List<int> _selectedDays = [];
  List<Map<String, dynamic>> _programs = [];
  List<ClassCoachOption> _coaches = [];
  String? _selectedProgramId;
  String? _selectedCoachId;
  Object? _coachesError;

  late final ClassCoachRepository _coachRepository =
      widget.coachRepository ?? SupabaseClassCoachRepository(widget.client!);

  @override
  void initState() {
    super.initState();
    _loadPrograms();
    _loadCoaches();
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
      final injectedLoader = widget.programsLoader;
      final programs = injectedLoader != null
          ? await injectedLoader()
          : List<Map<String, dynamic>>.from(
              await widget.client!
                  .from('programs')
                  .select('id, name')
                  .eq('gym_id', widget.gymId)
                  .eq('is_active', true)
                  .order('name'),
            );

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

  Future<void> _loadCoaches() async {
    setState(() {
      _loadingCoaches = true;
      _coachesError = null;
    });

    try {
      final coaches = await _coachRepository.listAssignable();
      if (!mounted) return;
      setState(() => _coaches = coaches);
    } catch (error) {
      if (!mounted) return;
      setState(() => _coachesError = error);
    } finally {
      if (mounted) setState(() => _loadingCoaches = false);
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
        !_loadingCoaches &&
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

        await widget.client!.rpc(
          'create_recurring_classes_multi',
          params: withRecurringClassCoach({
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
          }, _selectedCoachId),
        );
      } else if (_repeatWeekly) {
        await widget.client!.rpc(
          'create_recurring_classes',
          params: withRecurringClassCoach({
            'p_gym_id': widget.gymId,
            'p_program_id': program['id'],
            'p_title': programName,
            'p_starts_at': startsAt.toUtc().toIso8601String(),
            'p_duration_minutes': durationMinutes,
            'p_capacity': capacity,
            'p_weeks': 8,
          }, _selectedCoachId),
        );
      } else {
        await widget.client!
            .from('classes')
            .insert(
              withClassCoach({
                'gym_id': widget.gymId,
                'program_id': program['id'],
                'title': programName,
                'starts_at': startsAt.toUtc().toIso8601String(),
                'duration_minutes': durationMinutes,
                'capacity': capacity,
                'created_by': widget.client!.auth.currentUser?.id,
              }, _selectedCoachId),
            );
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
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.border(context),
                  width: 0.8,
                ),
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
                            color: AppColors.accent,
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
                            color: AppColors.textPrimary(context),
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
                32 + MediaQuery.of(context).viewInsets.bottom,
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
                  Text(
                    appStrings.classNeedProgram,
                    style: _ClassSheetText.body.copyWith(
                      color: AppColors.textPrimary(context),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedProgramId,
                    dropdownColor: AppColors.surface(context),
                    iconEnabledColor: AppColors.textSecondary(context),
                    style: GoogleFonts.barlow(
                      color: AppColors.textPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    hint: Text(
                      appStrings.workoutProgram,
                      style: GoogleFonts.barlow(
                        color: AppColors.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    decoration: _programDropdownInput(
                      context,
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
                            style: GoogleFonts.barlow(
                              color: AppColors.textPrimary(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedProgramId = value),
                  ),
                const SizedBox(height: 12),
                ClassCoachSelector(
                  coaches: _coaches,
                  selectedCoachId: _selectedCoachId,
                  loading: _loadingCoaches,
                  error: _coachesError,
                  onChanged: (coachId) =>
                      setState(() => _selectedCoachId = coachId),
                  onRetry: _loadCoaches,
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _duration,
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.barlow(
                          color: AppColors.textPrimary(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: _classSheetInput(
                          context,
                          appStrings.duration,
                          Icons.timer_outlined,
                          suffix: appStrings.minutesShort,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _capacity,
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.barlow(
                          color: AppColors.textPrimary(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: _classSheetInput(
                          context,
                          appStrings.capacity,
                          Icons.groups_outlined,
                          suffix: appStrings.placesLower,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt(context),
                    borderRadius: BorderRadius.circular(AppRadii.input),
                    border: Border.all(
                      color: AppColors.border(context),
                      width: 1,
                    ),
                  ),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                    activeThumbColor: AppColors.accent,
                    activeTrackColor: AppColors.accent.withValues(alpha: 0.28),
                    inactiveThumbColor: AppColors.textSecondary(context),
                    inactiveTrackColor: AppColors.border(context),
                    value: _repeatWeekly,
                    onChanged: (value) => setState(() => _repeatWeekly = value),
                    title: Text(
                      appStrings.repeatWeekly,
                      style: _ClassSheetText.rowTitle.copyWith(
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    subtitle: Text(
                      appStrings.repeatWeeklyDescription,
                      style: GoogleFonts.barlow(
                        color: AppColors.textSecondary(context),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                if (_repeatWeekly) ...[
                  const SizedBox(height: 12),
                  Text(
                    appStrings.repeatOn.toUpperCase(),
                    style: _ClassSheetText.section.copyWith(
                      color: AppColors.accent,
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
                          backgroundColor: AppColors.surfaceAlt(context),
                          selectedColor: AppColors.accent,
                          side: BorderSide(
                            color: AppColors.border(context),
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.input),
                          ),
                          labelStyle: _ClassSheetText.body.copyWith(
                            color: _selectedDays.contains(index + 1)
                                ? Colors.white
                                : AppColors.textPrimary(context),
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
                if (_isPastClass) ...[
                  const SizedBox(height: 12),
                  Text(
                    appStrings.chooseFutureDateTime,
                    style: _ClassSheetText.body.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],
                if (!_canCreate && !_loadingPrograms && !_loadingCoaches) ...[
                  const SizedBox(height: 14),
                  Text(
                    appStrings.classRequiredFieldsHint,
                    style: GoogleFonts.barlow(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _CreateClassButton(
                  label: appStrings.createClassTitle,
                  loading: _saving,
                  enabled: _canCreate,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _programDropdownInput(
  BuildContext context,
  String hint,
  IconData icon,
) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
    filled: true,
    fillColor: AppColors.surface(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
  );
}

InputDecoration _classSheetInput(
  BuildContext context,
  String hint,
  IconData icon, {
  required String suffix,
}) {
  return InputDecoration(
    labelText: hint,
    suffixText: suffix,
    labelStyle: GoogleFonts.barlow(
      color: AppColors.textSecondary(context),
      fontWeight: FontWeight.w600,
    ),
    suffixStyle: GoogleFonts.barlow(
      color: AppColors.textSecondary(context),
      fontWeight: FontWeight.w600,
    ),
    hintStyle: _ClassSheetText.subtle.copyWith(
      color: AppColors.textSecondary(context),
    ),
    prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
    filled: true,
    fillColor: AppColors.surface(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
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
              ? AppColors.accent
              : AppColors.surfaceAlt(context),
          disabledBackgroundColor: AppColors.surfaceAlt(context),
          foregroundColor: active
              ? Colors.white
              : AppColors.textSecondary(context),
          disabledForegroundColor: AppColors.textSecondary(context),
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
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppRadii.input),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.input),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _ClassSheetText.rowTitle.copyWith(
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.barlow(
                          color: AppColors.textSecondary(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
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
