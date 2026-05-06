import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';

import '../../../../core/widgets/app_outlined_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../../../core/widgets/app_button.dart';

Future<void> showCreateWorkoutSheet({
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
      final navigator = Navigator.of(context);
      navigator.pop();
      await widget.onCreated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create workout error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
              appStrings.workoutCreateTitle,
              style: GoogleFonts.barlowCondensed(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0E0E11),
                letterSpacing: -0.3,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 16),
            if (_loadingPrograms)
              const Center(child: CircularProgressIndicator())
            else if (_programs.isEmpty)
              Text(
                appStrings.workoutNeedProgram,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF384152),
                  height: 1.3,
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _programId,
                decoration: InputDecoration(
                  labelText: appStrings.workoutProgram,
                ),
                items: _programs
                    .map(
                      (p) => DropdownMenuItem(
                        value: p['id'].toString(),
                        child: Text(p['name']),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _programId = v),
              ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(appStrings.workoutDate),
              subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 7)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 12),

            AppOutlinedButton(
              label: appStrings.workoutSelectImage,
              onPressed: _pickImage,
            ),

            if (_image != null) ...[
              const SizedBox(height: 8),
              Image.file(_image!, height: 150),
            ],

            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: appStrings.workoutDescription,
                hintText: appStrings.workoutWriteWod,
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: appStrings.workoutCreateTitle,
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
