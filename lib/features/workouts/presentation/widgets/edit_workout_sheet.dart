import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_pickers.dart';

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
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _EditWorkoutSheet(
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
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.border(context),
                  width: 0.8,
                ),
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
                            color: AppColors.accent,
                            size: 34,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          appStrings.workoutEditTitle.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _EditWorkoutSheetText.title.copyWith(
                            color: AppColors.textPrimary(context),
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
                12,
                22,
                110 + MediaQuery.of(context).viewInsets.bottom,
              ),
              children: [
                if (_loadingPrograms)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _programId,
                    dropdownColor: AppColors.surface(context),
                    iconEnabledColor: AppColors.textSecondary(context),
                    style: _EditWorkoutSheetText.body.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _editWorkoutInput(
                      context,
                      '',
                      Icons.grid_view_rounded,
                    ),
                    items: _programs.map((p) {
                      return DropdownMenuItem<String>(
                        value: p['id'].toString(),
                        child: Text(
                          p['name']?.toString() ?? appStrings.workoutProgram,
                          style: _EditWorkoutSheetText.body.copyWith(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                    final picked = await showAppDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
                const SizedBox(height: 12),
                _EditWorkoutActionRow(
                  icon: Icons.image_outlined,
                  title: appStrings.changeImage,
                  subtitle: _image != null
                      ? appStrings.newImageSelected
                      : (_imageUrl != null && _imageUrl!.isNotEmpty
                            ? appStrings.currentImage
                            : appStrings.noImage),
                  onTap: _pickImage,
                ),
                if (_image != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                    child: Image.file(
                      _image!,
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ] else if (_imageUrl != null && _imageUrl!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _imageUrl!,
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
                  style: _EditWorkoutSheetText.body.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  decoration: InputDecoration(
                    labelText: null,
                    hintText: appStrings.workoutWriteWod,
                    alignLabelWithHint: true,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    labelStyle: _EditWorkoutSheetText.subtle.copyWith(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                    ),
                    hintStyle: _EditWorkoutSheetText.subtle.copyWith(
                      color: AppColors.textSecondary(context),
                      fontSize: 15,
                    ),
                    filled: true,
                    fillColor: AppColors.surface(context),
                    contentPadding: const EdgeInsets.fromLTRB(18, 26, 18, 22),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.input),
                      borderSide: BorderSide(
                        color: AppColors.border(context),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.input),
                      borderSide: const BorderSide(
                        color: AppColors.accent,
                        width: 1.2,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.input),
                      borderSide: BorderSide(
                        color: AppColors.border(context),
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
                color: AppColors.background(context),
                boxShadow: [...AppShadows.card(context)],
              ),
              child: _EditWorkoutButton(
                label: appStrings.workoutSaveChanges,
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

InputDecoration _editWorkoutInput(
  BuildContext context,
  String hint,
  IconData icon,
) {
  return InputDecoration(
    hintText: hint.isEmpty ? null : hint,
    labelText: null,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    hintStyle: _EditWorkoutSheetText.subtle,
    labelStyle: _EditWorkoutSheetText.subtle,
    prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
    filled: true,
    fillColor: AppColors.surface(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
  );
}

class _EditWorkoutSheetText {
  const _EditWorkoutSheetText._();

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

class _EditWorkoutButton extends StatelessWidget {
  const _EditWorkoutButton({
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
          disabledBackgroundColor: AppColors.isDark(context)
              ? AppColors.surface(context)
              : const Color(0xFFE9E9EC),
          foregroundColor: const Color(0xFF111111),
          disabledForegroundColor: AppColors.textSecondary(context),
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
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppRadii.input),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 20),
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
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
