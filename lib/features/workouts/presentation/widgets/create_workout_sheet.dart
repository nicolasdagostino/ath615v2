import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_large_form_sheet.dart';
import '../../../../core/widgets/app_pickers.dart';
import 'workout_form_controls.dart';

Future<void> showCreateWorkoutSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
  required Future<void> Function() onCreated,
  DateTime? initialDate,
}) async {
  await showAppLargeFormSheet(
    context: context,
    builder: (_) => _CreateWorkoutSheet(
      client: client,
      gymId: gymId,
      onCreated: onCreated,
      initialDate: initialDate,
    ),
  );
}

class _CreateWorkoutSheet extends StatefulWidget {
  const _CreateWorkoutSheet({
    required this.client,
    required this.gymId,
    required this.onCreated,
    this.initialDate,
  });

  final SupabaseClient client;
  final String gymId;
  final Future<void> Function() onCreated;
  final DateTime? initialDate;

  @override
  State<_CreateWorkoutSheet> createState() => _CreateWorkoutSheetState();
}

class _CreateWorkoutSheetState extends State<_CreateWorkoutSheet> {
  bool _loadingPrograms = true;
  bool _saving = false;

  List<Map<String, dynamic>> _programs = [];
  String? _programId;

  late DateTime _date;
  final _description = TextEditingController();
  File? _image;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
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
    return WorkoutFormScaffold(
      title: appStrings.workoutCreateTitle,
      onClose: () => Navigator.of(context).pop(),
      submit: WorkoutFormButton(
        label: appStrings.workoutCreateTitle,
        loading: _saving,
        enabled: _canSave,
        onPressed: _save,
      ),
      children: [
        WorkoutFormFields(
          loadingPrograms: _loadingPrograms,
          programs: _programs,
          programId: _programId,
          onProgramChanged: (value) => setState(() => _programId = value),
          dateLabel:
              '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
          onDateTap: () async {
            final picked = await showAppDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime.now().subtract(const Duration(days: 7)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _date = picked);
          },
          imageTitle: appStrings.workoutSelectImage,
          imageSubtitle: _image == null ? '' : appStrings.imageSelected,
          onImageTap: _pickImage,
          imagePreview: _image == null
              ? null
              : Image.file(
                  _image!,
                  height: 170,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
          onRemoveImage: _image == null
              ? null
              : () => setState(() => _image = null),
          descriptionController: _description,
        ),
      ],
    );
  }
}
