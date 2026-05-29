import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_pickers.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

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
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: ListView(
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7DAE0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  appStrings.classHistory.toUpperCase(),
                  style: _TrainingText.sectionTitle,
                ),
                const SizedBox(height: 14),
                if (_classHistory.isEmpty)
                  Text(appStrings.noClasses, style: _TrainingText.subtle)
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
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(title, style: _TrainingText.title),
                            ),
                            Text(date, style: _TrainingText.subtle),
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
      achievedAt.text =
          record['achieved_at']?.toString() ?? _dateInputValue(DateTime.now());
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Text(
                        appStrings.addRecord.toUpperCase(),
                        style: _TrainingText.sectionTitle,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedExercise,
                        decoration: _inputDecoration(appStrings.exercise),
                        items: _recordExercises.map((exercise) {
                          return DropdownMenuItem<String>(
                            value: exercise,
                            child: Text(exercise, style: _TrainingText.input),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() {
                            selectedExercise = value;
                            fillFromExisting(value);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: weight,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: _TrainingText.input,
                        decoration: _inputDecoration(appStrings.weightKg),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: achievedAt,
                        readOnly: true,
                        style: _TrainingText.input,
                        decoration: _inputDecoration(appStrings.birthDate)
                            .copyWith(
                              suffixIcon: const Icon(
                                Icons.calendar_month_rounded,
                              ),
                            ),
                        onTap: () async {
                          final current = DateTime.tryParse(achievedAt.text);
                          final now = DateTime.now();
                          final picked = await showAppDatePicker(
                            context: context,
                            initialDate: current ?? now,
                            firstDate: DateTime(2000),
                            lastDate: now,
                          );
                          if (picked == null) return;
                          setSheetState(() {
                            achievedAt.text = _dateInputValue(picked);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notes,
                        minLines: 2,
                        maxLines: 3,
                        style: _TrainingText.input,
                        decoration: _inputDecoration(appStrings.notes),
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

  Future<void> _openPersonalRecordsListSheet() async {
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: ListView(
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7DAE0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  appStrings.personalRecords.toUpperCase(),
                  style: _TrainingText.sectionTitle,
                ),
                const SizedBox(height: 14),
                if (_personalRecords.isEmpty)
                  Text(appStrings.noRecordsYet, style: _TrainingText.subtle)
                else
                  ..._personalRecords.map((record) {
                    final id = record['id']?.toString() ?? '';
                    final exercise = record['exercise_name']?.toString() ?? '-';
                    final weight = record['weight_kg']?.toString() ?? '-';
                    final date = _formatDate(record['achieved_at']?.toString());
                    final notes = record['notes']?.toString().trim() ?? '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await _openPersonalRecordSheet(
                              initialExercise: exercise,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        exercise,
                                        style: _TrainingText.title,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$weight kg · $date',
                                        style: _TrainingText.subtle,
                                      ),
                                      if (notes.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(notes, style: _TrainingText.body),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: id.isEmpty
                                      ? null
                                      : () async {
                                          Navigator.pop(sheetContext);
                                          await _deletePersonalRecord(id);
                                        },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFB42318),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                AppButton(
                  label: appStrings.addRecord,
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _openPersonalRecordSheet();
                  },
                ),
              ],
            ),
          ),
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

  Future<void> _deletePersonalRecord(String recordId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(appStrings.deleteRecordTitle),
          content: Text(appStrings.deleteRecordMsg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(appStrings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(appStrings.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('personal_records')
          .delete()
          .eq('id', recordId)
          .eq('user_id', userId);

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.deleteRecordError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
                const SizedBox(width: 8),
                Text('Training', style: _TrainingText.header),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              _TrainingMilestoneCard(attendedCount: _attendedCount),
              _TrainingPersonalRecordsCard(
                records: _personalRecords.take(5).toList(),
                onView: _openPersonalRecordsListSheet,
              ),
              _TrainingClassHistoryCard(
                history: _classHistory.take(5).toList(),
                formatDate: _formatDate,
                onViewAll: _openFullHistorySheet,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlowCondensed(
      color: const Color(0xFF8F96A3),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    filled: true,
    fillColor: const Color(0xFFF4F5F7),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
  );
}

class _TrainingText {
  const _TrainingText._();

  static TextStyle header = GoogleFonts.barlowCondensed(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: const Color(0xFF111827),
  );

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1.0,
  );

  static TextStyle sectionTitle = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: 0.8,
    height: 1.0,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.3,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
    letterSpacing: 0.3,
    height: 1.0,
  );

  static TextStyle input = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
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
            style: _TrainingText.sectionTitle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$attendedCount / $target ${appStrings.classesAttended}',
                  style: _TrainingText.title,
                ),
              ),
              Text(
                '$remaining ${appStrings.classesToGo}',
                style: _TrainingText.subtle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: const Color(0xFFE8EAF0),
              color: const Color(0xFFB59B6A),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingPersonalRecordsCard extends StatelessWidget {
  const _TrainingPersonalRecordsCard({
    required this.records,
    required this.onView,
  });

  final List<Map<String, dynamic>> records;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return _TrainingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appStrings.personalRecords.toUpperCase(),
            style: _TrainingText.sectionTitle,
          ),
          Text(
            records.isEmpty
                ? appStrings.noRecordsYet
                : '${records.length} ${appStrings.personalRecords}',
            style: _TrainingText.subtle,
          ),
          const SizedBox(height: 16),
          AppButton(label: appStrings.viewRecords, onPressed: onView),
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
            style: _TrainingText.sectionTitle,
          ),
          if (history.isEmpty)
            Text(appStrings.noClasses, style: _TrainingText.subtle)
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
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(title, style: _TrainingText.title)),
                      Text(date, style: _TrainingText.subtle),
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
