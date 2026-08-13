import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_pickers.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../data/class_coach_repository.dart';
import '../../domain/class_coach.dart';
import '../booking_colors.dart';
import 'class_coach_selector.dart';
import 'class_form_components.dart';

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
  final _title = TextEditingController();
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
    _title.dispose();
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
      final customTitle = _title.text.trim();
      final classTitle = customTitle.isEmpty ? programName : customTitle;

      if (classTitle.length > 100) {
        throw Exception(
          'El nombre de la clase no puede superar 100 caracteres.',
        );
      }

      final durationMinutes = int.tryParse(_duration.text.trim()) ?? 60;
      final capacity = int.tryParse(_capacity.text.trim()) ?? 12;

      if (_repeatWeekly && _selectedDays.isNotEmpty) {
        final time = TimeOfDay.fromDateTime(startsAt);

        await widget.client!.rpc(
          'create_recurring_classes_multi',
          params: withRecurringClassCoach({
            'p_gym_id': widget.gymId,
            'p_program_id': program['id'],
            'p_title': classTitle,
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
            'p_title': classTitle,
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
                'title': classTitle,
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

      await showAppMessageDialog(
        context: context,
        title: appStrings.error,
        message: e.toString().replaceFirst('Exception: ', ''),
        error: true,
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
      accentColor: BookingColors.primary,
    );

    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      accentColor: BookingColors.primary,
    );

    if (picked != null) setState(() => _selectedTime = picked);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return BookingClassFormScaffold(
      title: appStrings.createClassTitle,
      onClose: () => Navigator.of(context).pop(),
      submit: BookingClassSubmitButton(
        label: appStrings.createClassTitle,
        loading: _saving,
        enabled: _canCreate,
        onPressed: _save,
      ),
      children: [
        const BookingClassSectionLabel(label: 'NOMBRE DE LA CLASE'),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _title,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          style: appFormValueStyle(context),
          decoration: bookingClassInput(
            context,
            icon: Icons.edit_outlined,
            hintText: 'Opcional · usa el programa si queda vacío',
          ).copyWith(counterText: ''),
        ),
        const SizedBox(height: AppSpacing.lg),
        BookingClassSectionLabel(
          label: appStrings.workoutProgram.toUpperCase(),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_loadingPrograms)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: BookingColors.primary),
            ),
          )
        else if (_programs.isEmpty)
          Text(appStrings.classNeedProgram, style: AppTypography.body(context))
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedProgramId,
            isExpanded: true,
            dropdownColor: AppColors.surface(context),
            iconEnabledColor: AppColors.textSecondary(context),
            style: appFormValueStyle(context),
            hint: Text(
              appStrings.workoutProgram,
              style: appFormPlaceholderStyle(context),
            ),
            decoration: bookingClassInput(
              context,
              icon: Icons.fitness_center_outlined,
            ),
            items: [
              DropdownMenuItem<String>(
                enabled: false,
                child: Text(
                  appStrings.workoutProgram,
                  style: appFormPlaceholderStyle(context),
                ),
              ),
              ..._programs.map((program) {
                return DropdownMenuItem<String>(
                  value: program['id'].toString(),
                  child: Text(
                    program['name']?.toString() ?? appStrings.workoutProgram,
                    style: appFormValueStyle(context),
                  ),
                );
              }),
            ],
            onChanged: (value) => setState(() => _selectedProgramId = value),
          ),
        const SizedBox(height: AppSpacing.lg),
        BookingClassSectionLabel(
          label: appStrings.coachFieldLabel.toUpperCase(),
        ),
        const SizedBox(height: AppSpacing.xs),
        ClassCoachSelector(
          coaches: _coaches,
          selectedCoachId: _selectedCoachId,
          loading: _loadingCoaches,
          error: _coachesError,
          onChanged: (coachId) => setState(() => _selectedCoachId = coachId),
          onRetry: _loadCoaches,
          accentColor: BookingColors.primary,
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 260;
            final date = BookingClassPickerField(
              icon: Icons.calendar_month_outlined,
              label: appStrings.workoutDate,
              value: _selectedDate == null
                  ? appStrings.selectDate
                  : _formatDate(_selectedDate!),
              placeholder: _selectedDate == null,
              onTap: _pickDate,
            );
            final time = BookingClassPickerField(
              icon: Icons.schedule_rounded,
              label: appStrings.time,
              value: _selectedTime == null
                  ? appStrings.selectTime
                  : _selectedTime!.format(context),
              placeholder: _selectedTime == null,
              onTap: _pickTime,
            );
            if (compact) {
              return Column(
                children: [
                  date,
                  const SizedBox(height: AppSpacing.sm),
                  time,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: date),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: time),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        BookingClassSectionLabel(
          label:
              '${appStrings.duration.toUpperCase()} · ${appStrings.capacity.toUpperCase()}',
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _duration,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                keyboardType: TextInputType.number,
                style: appFormValueStyle(context),
                decoration: bookingClassInput(
                  context,
                  icon: Icons.timer_outlined,
                  suffix: appStrings.minutesShort,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: _capacity,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                keyboardType: TextInputType.number,
                style: appFormValueStyle(context),
                decoration: bookingClassInput(
                  context,
                  icon: Icons.groups_outlined,
                  suffix: appStrings.placesLower,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppRadii.input),
            border: Border.all(color: AppColors.border(context), width: 1),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            activeThumbColor: BookingColors.primary,
            activeTrackColor: BookingColors.primary.withValues(alpha: 0.28),
            inactiveThumbColor: AppColors.textSecondary(context),
            inactiveTrackColor: AppColors.border(context),
            value: _repeatWeekly,
            onChanged: (value) => setState(() => _repeatWeekly = value),
            title: Text(
              appStrings.repeatWeekly,
              style: AppTypography.itemTitle(context),
            ),
            subtitle: Text(
              appStrings.repeatWeeklyDescription,
              style: AppTypography.helper(context),
            ),
          ),
        ),
        if (_repeatWeekly) ...[
          const SizedBox(height: 12),
          Text(
            appStrings.repeatOn.toUpperCase(),
            style: AppTypography.sectionTitle(
              context,
            ).copyWith(color: BookingColors.primary),
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
                  selectedColor: BookingColors.primary,
                  side: BorderSide(color: AppColors.border(context), width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                  labelStyle: AppTypography.body(context).copyWith(
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
            style: AppTypography.error(context),
          ),
        ],
        if (!_canCreate && !_loadingPrograms && !_loadingCoaches) ...[
          const SizedBox(height: 14),
          Text(
            appStrings.classRequiredFieldsHint,
            style: AppTypography.helper(context),
          ),
        ],
      ],
    );
  }
}
