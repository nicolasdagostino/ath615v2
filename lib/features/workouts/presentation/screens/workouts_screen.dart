import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_selected_date_label.dart';
import '../../../../core/widgets/app_calendar_date_picker_sheet.dart';
import '../../../../core/widgets/app_week_date_selector.dart';
import '../../data/workouts_date_data_source.dart';
import '../workout_colors.dart';
import '../widgets/create_workout_sheet.dart';
import '../widgets/edit_workout_sheet.dart';
import '../widgets/manage_programs_sheet.dart';
import '../widgets/workout_card.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({
    super.key,
    required this.gymName,
    required this.unreadNotifications,
    required this.onOpenNotifications,
    this.dataSource,
    this.nowForTesting,
    this.initialDate,
  });

  final String? gymName;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;
  final WorkoutsDateDataSource? dataSource;
  final DateTime? nowForTesting;
  final DateTime? initialDate;

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  bool _loading = true;
  String? _role;
  String? _gymId;
  bool _isAccountActive = true;
  late DateTime _selectedDate;
  late DateTime _visibleWeek;
  List<Map<String, dynamic>> _workouts = [];

  SupabaseClient get _client => Supabase.instance.client;
  late final WorkoutsDateDataSource _dataSource =
      widget.dataSource ?? SupabaseWorkoutsDateDataSource(_client);
  DateTime get _today => _dateOnly(widget.nowForTesting ?? DateTime.now());
  bool get _canManage => _role == 'admin' || _role == 'owner';
  bool get _canSeeFuture => _role == 'admin';
  bool get _selectedIsFuture => _selectedDate.isAfter(_today);

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(widget.initialDate ?? _today);
    _visibleWeek = _startOfWeek(_selectedDate);
    _loadViewerAndDate();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _startOfWeek(DateTime date) =>
      _dateOnly(date.subtract(Duration(days: date.weekday - DateTime.monday)));

  Future<void> _loadViewerAndDate() async {
    setState(() => _loading = true);
    try {
      final viewer = await _dataSource.loadViewer();
      if (!mounted) return;
      _role = viewer.role;
      _gymId = viewer.gymId;
      _isAccountActive = viewer.isAccountActive;
      await _loadSelectedDate(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.workoutsLoadError(error))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSelectedDate({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final gymId = _gymId;
      final blockedAccount = _role == 'athlete' && !_isAccountActive;
      if (gymId == null ||
          blockedAccount ||
          (_selectedIsFuture && !_canSeeFuture)) {
        if (!mounted) return;
        setState(() {
          _workouts = [];
        });
        return;
      }
      final workouts = await _dataSource.loadForDate(
        gymId: gymId,
        date: _selectedDate,
      );
      if (!mounted) return;
      setState(() {
        _workouts = workouts;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.workoutsLoadError(error))),
      );
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _selectDate(DateTime date) async {
    setState(() {
      _selectedDate = _dateOnly(date);
      _visibleWeek = _startOfWeek(_selectedDate);
    });
    await _loadSelectedDate();
  }

  Future<void> _openMonthCalendar() async {
    final selected = await showAppCalendarDatePickerSheet(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      accentColor: WorkoutColors.primary,
    );
    if (selected != null) await _selectDate(selected);
  }

  void _moveWeek(int offset) {
    setState(() => _visibleWeek = _visibleWeek.add(Duration(days: offset * 7)));
  }

  Future<void> _openPrograms() async {
    final gymId = _gymId;
    if (gymId == null) return;
    await showManageProgramsSheet(
      context: context,
      client: _client,
      gymId: gymId,
    );
  }

  Future<void> _openCreateWorkout() async {
    final gymId = _gymId;
    if (gymId == null) return;
    await showCreateWorkoutSheet(
      context: context,
      client: _client,
      gymId: gymId,
      initialDate: _selectedDate,
      onCreated: _loadSelectedDate,
    );
  }

  Future<void> _editWorkout(Map<String, dynamic> workout) async {
    final gymId = _gymId;
    if (gymId == null) return;
    await showEditWorkoutSheet(
      context: context,
      client: _client,
      workoutId: workout['id'].toString(),
      gymId: gymId,
      currentProgramId: workout['program_id'].toString(),
      currentDescription: workout['description']?.toString() ?? '',
      currentDate: workout['workout_date'].toString(),
      currentImageUrl: workout['image_url']?.toString(),
      onUpdated: _loadSelectedDate,
    );
  }

  Future<void> _deleteWorkout(String workoutId) async {
    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: appStrings.workoutsDeleteTitle,
      message: appStrings.workoutsDeleteMessage,
      confirmLabel: appStrings.delete,
      cancelLabel: appStrings.cancel,
    );
    if (!confirmed) return;
    try {
      await _client.from('workouts').delete().eq('id', workoutId);
      await _loadSelectedDate();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.workoutsDeleteError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      floatingActionButton: _canManage
          ? _WorkoutAdminIsland(
              onPrograms: _openPrograms,
              onCreate: _openCreateWorkout,
            )
          : null,
      body: Column(
        children: [
          _WorkoutGymHeader(gymName: widget.gymName),
          const SizedBox(
            key: ValueKey('workout-header-content-spacing'),
            height: AppSpacing.md,
          ),
          WorkoutWeekCalendar(
            weekStart: _visibleWeek,
            selectedDate: _selectedDate,
            locale: appStrings.isEs ? 'es' : 'en',
            onSelected: _selectDate,
            onPreviousWeek: () => _moveWeek(-1),
            onNextWeek: () => _moveWeek(1),
          ),
          IconButton(
            key: const ValueKey('workout-open-month-calendar'),
            tooltip: appStrings.pick('Select date', 'Seleccionar fecha'),
            constraints: const BoxConstraints.tightFor(width: 48, height: 44),
            color: WorkoutColors.primary,
            onPressed: _openMonthCalendar,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
          ),
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: AppSelectedDateLabel(
              key: const ValueKey('workout-selected-date-label'),
              selectedDate: _selectedDate,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: WorkoutColors.primary,
              onRefresh: () => _loadSelectedDate(showLoading: false),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: WorkoutColors.primary,
                      ),
                    )
                  : _role == 'athlete' && !_isAccountActive
                  ? _WorkoutEmptyState(
                      icon: Icons.lock_outline_rounded,
                      message: appStrings.pick(
                        'Activate your account to access workouts.',
                        'Activa tu cuenta para acceder a los workouts.',
                      ),
                    )
                  : _workouts.isEmpty
                  ? _WorkoutEmptyState(
                      icon: _selectedIsFuture
                          ? Icons.calendar_today_outlined
                          : Icons.fitness_center_outlined,
                      message: _emptyMessage,
                    )
                  : ListView(
                      key: const ValueKey('workout-date-content'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenX,
                        0,
                        AppSpacing.screenX,
                        AppSpacing.xl + 72,
                      ),
                      children: [
                        for (
                          var index = 0;
                          index < _workouts.length;
                          index++
                        ) ...[
                          if (index > 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              child: Divider(height: 1, thickness: 0.8),
                            ),
                          _buildWorkoutCard(_workouts[index]),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String get _emptyMessage {
    if (_selectedIsFuture && !_canSeeFuture) {
      return appStrings.pick(
        'No workout is available for this date.',
        'No hay workout disponible para esta fecha.',
      );
    }
    if (_selectedDate == _today) {
      return appStrings.pick(
        'No workout has been published for today.',
        'No hay workout publicado para hoy.',
      );
    }
    return appStrings.pick(
      'No workout for this date.',
      'No hay workout para esta fecha.',
    );
  }

  Widget _buildWorkoutCard(Map<String, dynamic> workout) {
    final program = workout['programs'] as Map<String, dynamic>?;
    final likes = List<Map<String, dynamic>>.from(
      workout['workout_likes'] ?? [],
    );
    final comments =
        List<Map<String, dynamic>>.from(workout['workout_comments'] ?? [])
          ..sort(
            (a, b) => (b['created_at'] ?? '').toString().compareTo(
              (a['created_at'] ?? '').toString(),
            ),
          );
    return WorkoutCard(
      workoutId: workout['id'].toString(),
      program: program?['name']?.toString() ?? appStrings.workoutFallbackTitle,
      description: workout['description']?.toString() ?? '',
      date: workout['workout_date'].toString(),
      showDate: false,
      imageUrl: workout['image_url']?.toString(),
      likes: likes,
      comments: comments,
      canManage: _canManage,
      accentColor: WorkoutColors.primary,
      useEditAction: true,
      onEdit: () => _editWorkout(workout),
      onDelete: () => _deleteWorkout(workout['id'].toString()),
      onChanged: _loadSelectedDate,
    );
  }
}

class _WorkoutGymHeader extends StatelessWidget {
  const _WorkoutGymHeader({required this.gymName});

  final String? gymName;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('workout-gym-header'),
    color: WorkoutColors.primary,
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: AppSizes.mainHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
          child: Center(
            child: Text(
              (gymName ?? appStrings.appBrand).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _WorkoutAdminIsland extends StatelessWidget {
  const _WorkoutAdminIsland({required this.onPrograms, required this.onCreate});

  final VoidCallback onPrograms;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('workout-admin-island'),
    color: WorkoutColors.primary,
    elevation: 5,
    shadowColor: Colors.black.withValues(alpha: 0.24),
    borderRadius: BorderRadius.circular(AppRadii.pill),
    clipBehavior: Clip.antiAlias,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: appStrings.manageProgramsTitle,
          child: IconButton(
            key: const ValueKey('workout-programs'),
            tooltip: appStrings.manageProgramsTitle,
            constraints: const BoxConstraints.tightFor(width: 52, height: 52),
            color: Colors.white,
            onPressed: onPrograms,
            icon: const Icon(Icons.grid_view_rounded, size: 22),
          ),
        ),
        Container(
          width: 1,
          height: 24,
          color: Colors.white.withValues(alpha: 0.32),
        ),
        Semantics(
          button: true,
          label: appStrings.workoutCreate,
          child: IconButton(
            key: const ValueKey('workout-create'),
            tooltip: appStrings.workoutCreate,
            constraints: const BoxConstraints.tightFor(width: 52, height: 52),
            color: Colors.white,
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 26),
          ),
        ),
      ],
    ),
  );
}

class WorkoutWeekCalendar extends StatelessWidget {
  const WorkoutWeekCalendar({
    super.key,
    required this.weekStart,
    required this.selectedDate,
    required this.locale,
    required this.onSelected,
    required this.onPreviousWeek,
    required this.onNextWeek,
  });

  final DateTime weekStart;
  final DateTime selectedDate;
  final String locale;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('workout-week-calendar'),
    onHorizontalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      if (velocity < -120) onNextWeek();
      if (velocity > 120) onPreviousWeek();
    },
    child: AppWeekDateSelector(
      days: List.generate(7, (index) => weekStart.add(Duration(days: index))),
      selectedDay: selectedDate,
      weekdayLabel: (date) =>
          DateFormat('EEE', locale).format(date).toUpperCase(),
      onSelected: onSelected,
      accentColor: WorkoutColors.primary,
      physics: const NeverScrollableScrollPhysics(),
      itemKey: (date) =>
          ValueKey('workout-day-${date.toIso8601String().substring(0, 10)}'),
    ),
  );
}

class _WorkoutEmptyState extends StatelessWidget {
  const _WorkoutEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('workout-empty-state'),
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(28, 90, 28, 28),
    children: [
      Icon(icon, size: 38, color: WorkoutColors.primary),
      const SizedBox(height: AppSpacing.md),
      Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodySecondary(context),
      ),
    ],
  );
}
