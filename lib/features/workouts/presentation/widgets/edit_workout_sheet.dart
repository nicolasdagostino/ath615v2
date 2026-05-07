import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';

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
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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

      await widget.client.rpc(
        'schedule_workout_notifications',
        params: {'w_id': widget.workoutId},
      );

      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await widget.onUpdated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.workoutUpdateError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              Text(appStrings.workoutEditTitle.toUpperCase(), style: _EditWorkoutSheetText.title),
              const SizedBox(height: 16),
              if (_loadingPrograms)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFFB59B6A))),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _programId,
                  decoration: _editWorkoutInput(appStrings.workoutProgram, Icons.fitness_center_outlined),
                  items: _programs.map((p) {
                    return DropdownMenuItem<String>(
                      value: p['id'].toString(),
                      child: Text(p['name']?.toString() ?? appStrings.workoutProgram),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _programId = value);
                  },
                ),
              const SizedBox(height: 12),
              _EditWorkoutActionRow(
                icon: Icons.calendar_month_outlined,
                title: appStrings.workoutDate,
                subtitle: _formatDate(_date),
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
              _EditWorkoutActionRow(
                icon: Icons.image_outlined,
                title: 'Change image',
                subtitle: _image != null
                    ? 'New image selected'
                    : (_imageUrl != null && _imageUrl!.isNotEmpty ? 'Current image' : 'No image'),
                onTap: _pickImage,
              ),
              if (_image != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(_image!, height: 150, width: double.infinity, fit: BoxFit.cover),
                ),
              ] else if (_imageUrl != null && _imageUrl!.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(_imageUrl!, height: 150, width: double.infinity, fit: BoxFit.cover),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 6,
                style: _EditWorkoutSheetText.body,
                decoration: _editWorkoutInput(appStrings.workoutDescription, Icons.notes_rounded).copyWith(
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              AppButton(
                label: appStrings.workoutSaveChanges,
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

InputDecoration _editWorkoutInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    hintStyle: _EditWorkoutSheetText.subtle,
    labelStyle: _EditWorkoutSheetText.subtle,
    prefixIcon: Icon(icon, color: const Color(0xFF8F96A3), size: 20),
    filled: true,
    fillColor: const Color(0xFFF4F5F7),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
  );
}

class _EditWorkoutSheetText {
  const _EditWorkoutSheetText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle rowTitle = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle body = GoogleFonts.barlowCondensed(
    color: const Color(0xFF384152),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
    letterSpacing: 0.3,
    height: 1,
  );
}

class _EditWorkoutActionRow extends StatelessWidget {
  const _EditWorkoutActionRow({
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
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
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
                    Text(title, style: _EditWorkoutSheetText.rowTitle),
                    const SizedBox(height: 4),
                    Text(subtitle, style: _EditWorkoutSheetText.subtle),
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
