import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/widgets/app_large_form_sheet.dart';
import '../../../../core/widgets/app_pickers.dart';
import 'workout_form_controls.dart';

Future<void> showEditWorkoutSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String workoutId,
  required String gymId,
  required String currentProgramId,
  required String currentDescription,
  required String currentDate,
  String? currentImageUrl,
  required Future<void> Function() onUpdated,
}) async {
  await showAppLargeFormSheet(
    context: context,
    builder: (_) => _EditWorkoutSheet(
      client: client,
      workoutId: workoutId,
      gymId: gymId,
      currentProgramId: currentProgramId,
      currentDescription: currentDescription,
      currentDate: currentDate,
      currentImageUrl: currentImageUrl,
      onUpdated: onUpdated,
    ),
  );
}

class _EditWorkoutSheet extends StatefulWidget {
  const _EditWorkoutSheet({
    required this.client,
    required this.workoutId,
    required this.gymId,
    required this.currentProgramId,
    required this.currentDescription,
    required this.currentDate,
    this.currentImageUrl,
    required this.onUpdated,
  });

  final SupabaseClient client;
  final String workoutId;
  final String gymId;
  final String currentProgramId;
  final String currentDescription;
  final String currentDate;
  final String? currentImageUrl;
  final Future<void> Function() onUpdated;

  @override
  State<_EditWorkoutSheet> createState() => _EditWorkoutSheetState();
}

class _EditWorkoutSheetState extends State<_EditWorkoutSheet> {
  bool _loadingPrograms = true;
  bool _saving = false;
  List<Map<String, dynamic>> _programs = [];
  late String _programId;
  late DateTime _date;
  late final TextEditingController _description;
  File? _image;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _programId = widget.currentProgramId;
    _date = DateTime.tryParse(widget.currentDate) ?? DateTime.now();
    _imageUrl = widget.currentImageUrl;
    _description = TextEditingController(text: widget.currentDescription)
      ..addListener(_refreshForm);
    _loadPrograms();
  }

  void _refreshForm() {
    if (mounted) setState(() {});
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

    if (!mounted) return;
    setState(() {
      _programs = List<Map<String, dynamic>>.from(rows);
      _loadingPrograms = false;
    });
  }

  bool get _canSave => !_saving && _description.text.trim().isNotEmpty;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      String? imageUrl = _imageUrl;
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

      await widget.client
          .from('workouts')
          .update({
            'program_id': _programId,
            'workout_date': _date.toIso8601String().split('T').first,
            'description': _description.text.trim(),
            'image_url': imageUrl,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.workoutId);
      await widget.client.rpc(
        'schedule_workout_notifications',
        params: {'w_id': widget.workoutId},
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onUpdated();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.workoutUpdateError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  Widget? get _imagePreview {
    if (_image != null) {
      return Image.file(
        _image!,
        height: 170,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      return Image.network(
        _imageUrl!,
        height: 170,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => WorkoutFormScaffold(
    title: appStrings.workoutEditTitle,
    onClose: () => Navigator.of(context).pop(),
    submit: WorkoutFormButton(
      label: appStrings.workoutSaveChanges,
      loading: _saving,
      enabled: _canSave,
      onPressed: _save,
    ),
    children: [
      WorkoutFormFields(
        loadingPrograms: _loadingPrograms,
        programs: _programs,
        programId: _programId,
        onProgramChanged: (value) {
          if (value != null) setState(() => _programId = value);
        },
        dateLabel: _formatDate(_date),
        onDateTap: () async {
          final picked = await showAppDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) setState(() => _date = picked);
        },
        imageTitle: appStrings.changeImage,
        imageSubtitle: _image != null
            ? appStrings.newImageSelected
            : (_imageUrl != null && _imageUrl!.isNotEmpty
                  ? appStrings.currentImage
                  : appStrings.noImage),
        onImageTap: _pickImage,
        imagePreview: _imagePreview,
        onRemoveImage: _imagePreview == null
            ? null
            : () => setState(() {
                _image = null;
                _imageUrl = null;
              }),
        descriptionController: _description,
      ),
    ],
  );
}
