import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_large_form_sheet.dart';
import '../../data/class_coach_repository.dart';
import '../../domain/class_coach.dart';
import '../booking_colors.dart';
import 'class_coach_selector.dart';
import 'class_form_components.dart';

Future<void> showEditClassSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
  required Map<String, dynamic> klass,
  required Future<void> Function() onUpdated,
  ClassCoachRepository? coachRepository,
  Future<List<Map<String, dynamic>>> Function()? programsLoader,
}) async {
  await showAppLargeFormSheet(
    context: context,
    builder: (_) => _EditClassSheet(
      client: client,
      gymId: gymId,
      klass: klass,
      onUpdated: onUpdated,
      coachRepository: coachRepository,
      programsLoader: programsLoader,
    ),
  );
}

class _EditClassSheet extends StatefulWidget {
  const _EditClassSheet({
    required this.client,
    required this.gymId,
    required this.klass,
    required this.onUpdated,
    this.coachRepository,
    this.programsLoader,
  });

  final SupabaseClient client;
  final String gymId;
  final Map<String, dynamic> klass;
  final Future<void> Function() onUpdated;
  final ClassCoachRepository? coachRepository;
  final Future<List<Map<String, dynamic>>> Function()? programsLoader;

  @override
  State<_EditClassSheet> createState() => _EditClassSheetState();
}

class _EditClassSheetState extends State<_EditClassSheet> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  late final TextEditingController _title;
  late final TextEditingController _duration;
  late final TextEditingController _capacity;

  bool _loadingPrograms = true;
  bool _loadingCoaches = true;
  bool _saving = false;
  List<Map<String, dynamic>> _programs = [];
  List<ClassCoachOption> _coaches = [];
  String? _selectedProgramId;
  String? _selectedCoachId;
  late final String? _currentCoachId;
  late final String? _currentCoachName;
  Object? _coachesError;

  late final ClassCoachRepository _coachRepository =
      widget.coachRepository ?? SupabaseClassCoachRepository(widget.client);

  @override
  void initState() {
    super.initState();

    final startsAt = DateTime.parse(widget.klass['starts_at']).toLocal();

    _selectedDate = DateTime(startsAt.year, startsAt.month, startsAt.day);
    _selectedTime = TimeOfDay.fromDateTime(startsAt);
    _title = TextEditingController(
      text: widget.klass['title']?.toString() ?? '',
    );
    _duration = TextEditingController(
      text: (widget.klass['duration_minutes'] ?? 60).toString(),
    );
    _capacity = TextEditingController(
      text: (widget.klass['capacity'] ?? 12).toString(),
    );
    _selectedProgramId = widget.klass['program_id']?.toString();
    _currentCoachId = widget.klass['coach_id']?.toString();
    _selectedCoachId = _currentCoachId;
    _currentCoachName = _coachName(widget.klass['coach']);

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
              await widget.client
                  .from('programs')
                  .select('id, name')
                  .eq('gym_id', widget.gymId)
                  .eq('is_active', true)
                  .order('name'),
            );

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
      ).showSnackBar(SnackBar(content: Text(appStrings.programsLoadError(e))));
    } finally {
      if (mounted) setState(() => _loadingPrograms = false);
    }
  }

  String? _coachName(Object? value) {
    if (value is Map) return value['full_name']?.toString();
    if (value is List && value.isNotEmpty && value.first is Map) {
      return (value.first as Map)['full_name']?.toString();
    }
    return null;
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

  bool get _canSave {
    return !_loadingPrograms &&
        !_loadingCoaches &&
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

      if (startsAt == null) throw Exception(appStrings.selectDateTime);
      if (program == null) throw Exception(appStrings.selectProgram);

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

      await widget.client
          .from('classes')
          .update(
            withClassCoach({
              'program_id': program['id'],
              'title': classTitle,
              'starts_at': startsAt.toUtc().toIso8601String(),
              'duration_minutes': durationMinutes,
              'capacity': capacity,
            }, _selectedCoachId),
          )
          .eq('id', widget.klass['id']);

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onUpdated();
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
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      accentColor: BookingColors.primary,
    );

    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
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
      title: appStrings.editClass,
      onClose: () => Navigator.of(context).pop(),
      submit: BookingClassSubmitButton(
        label: appStrings.workoutSaveChanges,
        loading: _saving,
        enabled: _canSave,
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
          currentCoachId: _currentCoachId,
          currentCoachName: _currentCoachName,
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
      ],
    );
  }
}
