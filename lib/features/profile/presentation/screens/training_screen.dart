import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_detail_header.dart';
import '../../../../core/widgets/app_button.dart';

Color _profileHubBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF252525) : const Color(0xFFF1F2F4);
}

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key, this.recordsOnly = false});

  final bool recordsOnly;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  List<Map<String, dynamic>> _personalRecords = [];
  List<Map<String, dynamic>> _classHistory = [];
  int _attendedCount = 0;
  bool _loading = true;

  static const List<String> _recordExercises = [
    'Back Squat',
    'Front Squat',
    'Overhead Squat',
    'Deadlift',
    'Strict Press',
    'Push Press',
    'Push Jerk',
    'Split Jerk',
    'Bench Press',
    'Clean',
    'Power Clean',
    'Squat Clean',
    'Hang Clean',
    'Snatch',
    'Power Snatch',
    'Squat Snatch',
    'Hang Snatch',
    'Clean & Jerk',
    'Thruster',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final attended = await Supabase.instance.client
        .from('class_bookings')
        .select('id')
        .eq('user_id', userId)
        .eq('status', 'attended');

    final history = await Supabase.instance.client
        .from('class_bookings')
        .select('id, status, classes(title, starts_at)')
        .eq('user_id', userId)
        .eq('status', 'attended')
        .order('created_at', ascending: false)
        .limit(20);

    final records = await Supabase.instance.client
        .from('personal_records')
        .select('id, exercise_name, weight_kg, achieved_at, notes')
        .eq('user_id', userId)
        .order('achieved_at', ascending: false)
        .order('created_at', ascending: false)
        .limit(8);

    if (!mounted) return;

    setState(() {
      _attendedCount = List<Map<String, dynamic>>.from(attended).length;
      _classHistory = List<Map<String, dynamic>>.from(history);
      _personalRecords = List<Map<String, dynamic>>.from(records);
      _loading = false;
    });
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.day}/${date.month}/${date.year}';
  }

  String _dateInputValue(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Map<String, dynamic>? _personalRecordForExercise(String exerciseName) {
    for (final record in _personalRecords) {
      if (record['exercise_name']?.toString() == exerciseName) {
        return record;
      }
    }
    return null;
  }

  Future<void> _openFullHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
            ),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(AppRadii.sheet),
              border: Border.all(color: AppColors.border(context), width: 1),
            ),
            child: ListView(
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.border(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  appStrings.classHistory.toUpperCase(),
                  style: _TrainingText.sectionTitle.copyWith(
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 14),
                if (_classHistory.isEmpty)
                  Text(
                    appStrings.noClasses,
                    style: _TrainingText.subtle.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  )
                else
                  ..._classHistory.map((item) {
                    final klass =
                        item['classes'] as Map<String, dynamic>? ?? {};
                    final title =
                        klass['title']?.toString() ?? appStrings.classFallback;
                    final date = _formatDate(klass['starts_at']?.toString());

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.border(context),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: _TrainingText.title.copyWith(
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    appStrings.attended.toUpperCase(),
                                    style: _TrainingText.subtle.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface(context),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFF323232),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                date,
                                style: _TrainingText.subtle.copyWith(
                                  color: AppColors.textSecondary(context),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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
  }

  Future<void> _openPersonalRecordSheet({String? initialExercise}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('gym_id')
        .eq('id', userId)
        .maybeSingle();

    if (!mounted) return;

    final gymId = profile?['gym_id']?.toString();
    if (gymId == null || gymId.isEmpty) return;

    String selectedExercise = initialExercise ?? _recordExercises.first;
    final weight = TextEditingController();
    final notes = TextEditingController();
    final achievedAt = TextEditingController(
      text: _dateInputValue(DateTime.now()),
    );

    void fillFromExisting(String exerciseName) {
      final record = _personalRecordForExercise(exerciseName);
      if (record == null) {
        weight.clear();
        notes.clear();
        achievedAt.text = _dateInputValue(DateTime.now());
        return;
      }

      weight.text = record['weight_kg']?.toString() ?? '';
      notes.text = record['notes']?.toString() ?? '';
      achievedAt.text = _dateInputValue(DateTime.now());
    }

    fillFromExisting(selectedExercise);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.border(context),
                      width: 1,
                    ),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.fitness_center_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              appStrings.addRecord.toUpperCase(),
                              style: _TrainingText.sectionTitle.copyWith(
                                fontSize: 20,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: AppColors.surface(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.border(context),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedExercise,
                                style: _TrainingText.input.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              appStrings.exercise.toUpperCase(),
                              style: _TrainingText.subtle.copyWith(
                                color: AppColors.textSecondary(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: weight,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        cursorColor: AppColors.primary,
                        style: _TrainingText.input.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: _inputDecoration(
                          context,
                          appStrings.weightKg,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notes,
                        minLines: 2,
                        maxLines: 3,
                        cursorColor: AppColors.primary,
                        style: _TrainingText.input.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: _inputDecoration(context, appStrings.notes),
                      ),
                      const SizedBox(height: 16),
                      AppButton(
                        label:
                            _personalRecords.any(
                              (r) =>
                                  r['exercise_name']?.toString() ==
                                  selectedExercise,
                            )
                            ? appStrings.updateRecord
                            : appStrings.addRecord,
                        onPressed: () async {
                          await _savePersonalRecord(
                            userId: userId,
                            gymId: gymId,
                            exerciseName: selectedExercise,
                            weightKg: weight.text,
                            achievedAt: achievedAt.text,
                            notes: notes.text,
                          );
                          if (mounted && sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _savePersonalRecord({
    required String userId,
    required String gymId,
    required String exerciseName,
    required String weightKg,
    required String achievedAt,
    required String notes,
  }) async {
    final parsedWeight = double.tryParse(weightKg.replaceAll(',', '.'));
    final exercise = exerciseName.trim();

    if (exercise.isEmpty || parsedWeight == null) return;

    try {
      final existing = _personalRecords.where(
        (r) => r['exercise_name']?.toString() == exercise,
      );

      final payload = {
        'user_id': userId,
        'gym_id': gymId,
        'exercise_name': exercise,
        'weight_kg': parsedWeight,
        'achieved_at': achievedAt,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
      };

      if (existing.isEmpty) {
        await Supabase.instance.client.from('personal_records').insert(payload);
      } else {
        await Supabase.instance.client
            .from('personal_records')
            .update(payload)
            .eq('id', existing.first['id'])
            .eq('user_id', userId);
      }

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.recordSaved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.saveRecordError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _profileHubBackground(context),
      body: ListView(
          padding: EdgeInsets.zero,
          children: [
            AppDetailHeader(
              title: widget.recordsOnly
                  ? appStrings.personalRecords
                  : appStrings.profileTraining,
              onBack: context.pop,
              leadingColor: AppColors.primary,
            ),
            _TrainingMenuSection(
              children: [
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                else if (widget.recordsOnly)
                  _TrainingRecordsHubCard(
                    recordExercises: _recordExercises,
                    personalRecordForExercise: _personalRecordForExercise,
                    formatDate: _formatDate,
                    onAdd: () => _openPersonalRecordSheet(),
                    onEdit: (exercise) =>
                        _openPersonalRecordSheet(initialExercise: exercise),
                  )
                else ...[
                  _TrainingMilestoneCard(attendedCount: _attendedCount),
                  _TrainingClassHistoryCard(
                    history: _classHistory.take(3).toList(),
                    formatDate: _formatDate,
                    onViewAll: _openFullHistorySheet,
                  ),
                ],
              ],
            ),
          ],
      ),
    );
  }
}

InputDecoration _inputDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlowCondensed(
      color: AppColors.textSecondary(context),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    labelText: null,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    filled: true,
    fillColor: AppColors.surface(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
  );
}

class _TrainingText {
  const _TrainingText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle sectionTitle = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.8,
    height: 1.0,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABABAB),
    letterSpacing: 0.3,
    height: 1.0,
  );

  static TextStyle input = GoogleFonts.barlowCondensed(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}

class _TrainingMenuSection extends StatelessWidget {
  const _TrainingMenuSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      color: _profileHubBackground(context),
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 72),
      child: Column(children: children),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context), width: 1),
        boxShadow: AppShadows.card(context),
      ),
      child: child,
    );
  }
}

class _TrainingMilestoneCard extends StatelessWidget {
  const _TrainingMilestoneCard({required this.attendedCount});

  final int attendedCount;

  int get _target {
    for (final target in [50, 100, 200, 500]) {
      if (attendedCount < target) return target;
    }
    return 500;
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final progress = target == 0
        ? 0.0
        : (attendedCount / target).clamp(0.0, 1.0);
    final remaining = (target - attendedCount).clamp(0, target);

    return _TrainingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.milestone.toUpperCase(),
            style: _TrainingText.sectionTitle.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$attendedCount / $target ${appStrings.classesAttended}',
                  style: _TrainingText.title.copyWith(
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              Text(
                '$remaining ${appStrings.classesToGo}',
                style: _TrainingText.subtle.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: AppColors.surface(context),
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingRecordsHubCard extends StatelessWidget {
  const _TrainingRecordsHubCard({
    required this.recordExercises,
    required this.personalRecordForExercise,
    required this.formatDate,
    required this.onAdd,
    required this.onEdit,
  });

  final List<String> recordExercises;
  final Map<String, dynamic>? Function(String exercise)
  personalRecordForExercise;
  final String Function(String? raw) formatDate;
  final VoidCallback onAdd;
  final void Function(String exercise) onEdit;

  @override
  Widget build(BuildContext context) {
    return _TrainingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.personalRecords.toUpperCase(),
            style: _TrainingText.sectionTitle.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 14),
          ...recordExercises.map((exercise) {
            final record = personalRecordForExercise(exercise);
            final weight = record?['weight_kg']?.toString();
            final date = formatDate(record?['achieved_at']?.toString());

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onEdit(exercise),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.border(context),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          exercise,
                          style: _TrainingText.title.copyWith(
                            color: AppColors.textPrimary(context),
                            fontSize: 17,
                          ),
                        ),
                      ),
                      if (record == null)
                        Text(
                          appStrings.notSet.toUpperCase(),
                          style: _TrainingText.subtle.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        Text(
                          '$weight kg · $date',
                          style: _TrainingText.subtle.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: AppColors.textSecondary(context),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TrainingClassHistoryCard extends StatelessWidget {
  const _TrainingClassHistoryCard({
    required this.history,
    required this.formatDate,
    required this.onViewAll,
  });

  final List<Map<String, dynamic>> history;
  final String Function(String? raw) formatDate;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return _TrainingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.classHistory.toUpperCase(),
            style: _TrainingText.sectionTitle.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 10),
          if (history.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt(context),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.primary, width: 1),
              ),
              child: Text(
                '${appStrings.attended.toUpperCase()} ${history.length}',
                style: _TrainingText.subtle.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (history.isEmpty)
            Text(
              appStrings.noClasses,
              style: _TrainingText.subtle.copyWith(
                color: AppColors.textSecondary(context),
              ),
            )
          else
            ...history.map((item) {
              final klass = item['classes'] as Map<String, dynamic>? ?? {};
              final title =
                  klass['title']?.toString() ?? appStrings.classFallback;
              final date = formatDate(klass['starts_at']?.toString());

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.border(context),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: _TrainingText.title.copyWith(
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt(context),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.border(context),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          date.toUpperCase(),
                          style: _TrainingText.subtle.copyWith(
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          AppButton(label: appStrings.viewAllHistory, onPressed: onViewAll),
        ],
      ),
    );
  }
}
