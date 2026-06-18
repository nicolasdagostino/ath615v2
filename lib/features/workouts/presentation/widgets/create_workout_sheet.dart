import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../../../core/widgets/app_pickers.dart';

Future<void> showCreateWorkoutSheet({
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
        _CreateWorkoutSheet(client: client, gymId: gymId, onCreated: onCreated),
  );
}

class _CreateWorkoutSheet extends StatefulWidget {
  const _CreateWorkoutSheet({
    required this.client,
    required this.gymId,
    required this.onCreated,
  });

  final SupabaseClient client;
  final String gymId;
  final Future<void> Function() onCreated;

  @override
  State<_CreateWorkoutSheet> createState() => _CreateWorkoutSheetState();
}

class _CreateWorkoutSheetState extends State<_CreateWorkoutSheet> {
  bool _loadingPrograms = true;
  bool _saving = false;

  List<Map<String, dynamic>> _programs = [];
  String? _programId;

  DateTime _date = DateTime.now();
  final _description = TextEditingController();
  File? _image;

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
    _loadPrograms();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadPrograms() async {
    final rows = await widget.client
        .from('programs')
        .select('id, name')
        .eq('gym_id', widget.gymId)
        .eq('is_active', true)
        .order('name');

    final list = List<Map<String, dynamic>>.from(rows);

    if (!mounted) return;
    setState(() {
      _programs = list;
      _programId = list.isEmpty ? null : list.first['id'].toString();
      _loadingPrograms = false;
    });
  }

  Map<String, dynamic>? get _program {
    for (final p in _programs) {
      if (p['id'].toString() == _programId) return p;
    }
    return null;
  }

  bool get _canSave =>
      !_saving && _program != null && _description.text.trim().isNotEmpty;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() => _saving = true);

    try {
      String? imageUrl;

      if (_image != null) {
        final fileName = DateTime.now().millisecondsSinceEpoch.toString();
        final path = 'workouts/$fileName.jpg';

        await widget.client.storage
            .from('workout-images')
            .upload(path, _image!);

        imageUrl = widget.client.storage
            .from('workout-images')
            .getPublicUrl(path);
      }

      final workout = await widget.client
          .from('workouts')
          .insert({
            'gym_id': widget.gymId,
            'program_id': _program!['id'],
            'workout_date': _date.toIso8601String().split('T').first,
            'description': _description.text.trim(),
            'image_url': imageUrl,
            'created_by': widget.client.auth.currentUser?.id,
          })
          .select('id')
          .single();

      await widget.client.rpc(
        'schedule_workout_notifications',
        params: {'w_id': workout['id']},
      );

      if (!mounted) return;

      FocusScope.of(context).unfocus();
      final navigator = Navigator.of(context);

      navigator.pop();

      await widget.onCreated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.createWorkoutError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                          appStrings.workoutCreateTitle.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _WorkoutSheetText.title.copyWith(
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
                22,
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
                  Text(
                    appStrings.workoutNeedProgram,
                    style: _WorkoutSheetText.body,
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _programId,
                    dropdownColor: const Color(0xFF171717),
                    iconEnabledColor: const Color(0xFFABABAB),
                    style: _WorkoutSheetText.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    hint: Text(
                      appStrings.workoutProgram,
                      style: _WorkoutSheetText.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    decoration:
                        _programDropdownInput(
                          appStrings.workoutProgram,
                          Icons.grid_view_rounded,
                        ).copyWith(
                          labelText: null,
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                        ),
                    items: [
                      DropdownMenuItem<String>(
                        enabled: false,
                        child: Text(
                          appStrings.workoutProgram,
                          style: _WorkoutSheetText.subtle.copyWith(
                            color: const Color(0xFFABABAB),
                          ),
                        ),
                      ),
                      ..._programs.map((p) {
                        return DropdownMenuItem<String>(
                          value: p['id'].toString(),
                          child: Text(
                            p['name']?.toString() ?? appStrings.workoutProgram,
                          ),
                        );
                      }),
                    ],
                    onChanged: (v) => setState(() => _programId = v),
                  ),
                const SizedBox(height: 12),
                _WorkoutSheetActionRow(
                  icon: Icons.calendar_month_outlined,
                  title: appStrings.workoutDate,
                  subtitle: '${_date.day}/${_date.month}/${_date.year}',
                  onTap: () async {
                    final picked = await showAppDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 7),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
                const SizedBox(height: 12),
                _WorkoutSheetActionRow(
                  icon: Icons.image_outlined,
                  title: appStrings.workoutSelectImage,
                  subtitle: _image == null ? '' : appStrings.imageSelected,
                  onTap: _pickImage,
                ),
                if (_image != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      _image!,
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  minLines: 10,
                  maxLines: 18,
                  keyboardType: TextInputType.multiline,
                  style: _WorkoutSheetText.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  decoration: InputDecoration(
                    labelText: null,
                    hintText: appStrings.workoutWriteWod,
                    alignLabelWithHint: true,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    labelStyle: _WorkoutSheetText.subtle.copyWith(
                      color: const Color(0xFFABABAB),
                      fontSize: 13,
                    ),
                    hintStyle: _WorkoutSheetText.subtle.copyWith(
                      color: const Color(0xFFABABAB),
                      fontSize: 15,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF171717),
                    contentPadding: const EdgeInsets.fromLTRB(18, 26, 18, 22),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFB59B6A),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFB59B6A),
                        width: 1.2,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFB59B6A),
                        width: 1,
                      ),
                    ),
                  ),
                ),
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
              child: _CreateWorkoutButton(
                label: appStrings.workoutCreateTitle,
                loading: _saving,
                enabled: _canSave,
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

class _WorkoutSheetText {
  const _WorkoutSheetText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.3,
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

class _CreateWorkoutButton extends StatelessWidget {
  const _CreateWorkoutButton({
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
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: loading || !enabled ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFB59B6A),
          disabledBackgroundColor: const Color(0xFF171717),
          foregroundColor: const Color(0xFF111111),
          disabledForegroundColor: const Color(0xFF6F6F6F),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF111111),
                ),
              )
            : Text(
                label.toUpperCase(),
                style: GoogleFonts.barlowCondensed(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  height: 1,
                ),
              ),
      ),
    );
  }
}

class _WorkoutSheetActionRow extends StatelessWidget {
  const _WorkoutSheetActionRow({
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
        borderRadius: BorderRadius.circular(10),
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
                    Text(title, style: _WorkoutSheetText.rowTitle),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: _WorkoutSheetText.subtle),
                    ],
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
