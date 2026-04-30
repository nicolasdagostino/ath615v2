import 'package:flutter/material.dart';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';

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
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
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
    _description = TextEditingController(text: widget.currentDescription);
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

    if (!mounted) return;
    setState(() {
      _programs = List<Map<String, dynamic>>.from(rows);
      _loadingPrograms = false;
    });
  }

  bool get _canSave => !_saving && _description.text.trim().isNotEmpty;

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

      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await widget.onUpdated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update workout error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Edit workout',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            if (_loadingPrograms)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<String>(
                initialValue: _programId,
                decoration: const InputDecoration(labelText: 'Program'),
                items: _programs
                    .map(
                      (p) => DropdownMenuItem(
                        value: p['id'].toString(),
                        child: Text(p['name']?.toString() ?? 'Program'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _programId = value);
                },
              ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_formatDate(_date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _pickImage,
              child: const Text('Change image'),
            ),
            if (_image != null) ...[
              const SizedBox(height: 8),
              Image.file(_image!, height: 150),
            ] else if (_imageUrl != null && _imageUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Image.network(_imageUrl!, height: 150),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Workout description',
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: 'Save changes',
              loading: _saving,
              onPressed: _canSave ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}
