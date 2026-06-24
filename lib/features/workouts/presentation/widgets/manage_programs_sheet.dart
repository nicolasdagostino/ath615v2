import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

Future<void> showManageProgramsSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
}) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) =>
        _ManageProgramsSheet(client: client, gymId: gymId),
  );
}

class _ManageProgramsSheet extends StatefulWidget {
  const _ManageProgramsSheet({required this.client, required this.gymId});

  final SupabaseClient client;
  final String gymId;

  @override
  State<_ManageProgramsSheet> createState() => _ManageProgramsSheetState();
}

class _ManageProgramsSheetState extends State<_ManageProgramsSheet> {
  final _name = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _programs = [];
  File? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.client
          .from('programs')
          .select('id, name, is_active, image_url, workouts(count)')
          .eq('gym_id', widget.gymId)
          .order('name');

      if (!mounted) return;
      setState(() => _programs = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.programsLoadError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      String? imageUrl;

      if (_image != null) {
        final fileName = DateTime.now().millisecondsSinceEpoch.toString();

        final path = 'programs/$fileName.jpg';

        await widget.client.storage
            .from('workout-images')
            .upload(path, _image!);

        imageUrl = widget.client.storage
            .from('workout-images')
            .getPublicUrl(path);
      }

      await widget.client.from('programs').insert({
        'gym_id': widget.gymId,
        'name': name,
        'image_url': imageUrl,
      });

      _name.clear();
      _image = null;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.createProgramError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateProgramImage(Map<String, dynamic> program) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked == null) return;

    final id = program['id'].toString();

    try {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final path = 'programs/$id-$fileName.jpg';
      final file = File(picked.path);

      await widget.client.storage.from('workout-images').upload(path, file);

      final imageUrl = widget.client.storage
          .from('workout-images')
          .getPublicUrl(path);

      setState(() {
        program['image_url'] = imageUrl;
      });

      await widget.client
          .from('programs')
          .update({'image_url': imageUrl})
          .eq('id', id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.programsLoadError(e))));
    }
  }

  Future<void> _renameProgram(Map<String, dynamic> program) async {
    final id = program['id'].toString();
    final controller = TextEditingController(
      text: program['name']?.toString() ?? '',
    );

    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
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
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border(context), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.workoutEdit.toUpperCase(),
                    style: _ProgramsText.title.copyWith(
                      color: AppColors.textPrimary(context),
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    cursorColor: AppColors.accent,
                    style: _ProgramsText.body.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _programsInput(
                      context,
                      appStrings.programName,
                      Icons.grid_view_rounded,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ProgramSecondaryButton(
                          label: appStrings.cancel,
                          onTap: () => Navigator.pop(sheetContext),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ProgramButton(
                          label: appStrings.save,
                          loading: false,
                          enabled: true,
                          onPressed: () {
                            Navigator.pop(sheetContext, controller.text.trim());
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (newName == null || newName.isEmpty) return;
    if (newName == (program['name']?.toString() ?? '')) return;

    final previousName = program['name'];

    setState(() {
      program['name'] = newName;
    });

    try {
      await widget.client
          .from('programs')
          .update({'name': newName})
          .eq('id', id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        program['name'] = previousName;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.programsLoadError(e))));
    }
  }

  Future<void> _showProgramOptions(Map<String, dynamic> program) async {
    final name = program['name']?.toString() ?? appStrings.workoutProgram;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border(context), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    name.toUpperCase(),
                    style: _ProgramsText.title.copyWith(
                      color: AppColors.textPrimary(context),
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appStrings.workoutOptions.toUpperCase(),
                    style: _ProgramsText.subtle.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ProgramSheetAction(
                    icon: Icons.edit_outlined,
                    label: appStrings.workoutEdit,
                    subtitle: name,
                    onTap: () {
                      Navigator.pop(context);
                      _renameProgram(program);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ProgramSheetAction(
                    icon: Icons.image_outlined,
                    label: appStrings.changeImage,
                    subtitle: name,
                    onTap: () {
                      Navigator.pop(context);
                      _updateProgramImage(program);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ProgramSheetAction(
                    icon: Icons.delete_outline,
                    label: appStrings.workoutDelete,
                    subtitle: name,
                    danger: true,
                    onTap: () {
                      Navigator.pop(context);
                      _deleteProgram(program);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteProgram(Map<String, dynamic> program) async {
    final id = program['id'].toString();
    final name = program['name']?.toString() ?? appStrings.workoutProgram;
    final workoutCount =
        ((program['workouts'] as List?)?.firstOrNull
            as Map<String, dynamic>?)?['count'] ??
        0;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
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
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border(context), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.danger,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          appStrings.delete.toUpperCase(),
                          style: _ProgramsText.title.copyWith(
                            color: AppColors.textPrimary(context),
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$name\n$workoutCount ${workoutCount == 1 ? appStrings.workoutFallbackTitle : appStrings.workoutsTitle}\n\n${appStrings.deleteProgramWarning}',
                    style: _ProgramsText.body.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ProgramSecondaryButton(
                          label: appStrings.cancel,
                          onTap: () => Navigator.pop(sheetContext, false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ProgramDangerButton(
                          label: appStrings.delete,
                          onTap: () => Navigator.pop(sheetContext, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    try {
      await widget.client.from('workouts').delete().eq('program_id', id);
      await widget.client.from('programs').delete().eq('id', id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.programsLoadError(e))));
    }
  }

  Future<void> _toggle(Map<String, dynamic> program) async {
    final id = program['id'].toString();
    final active = program['is_active'] == true;
    final next = !active;

    setState(() {
      program['is_active'] = next;
    });

    try {
      await widget.client
          .from('programs')
          .update({'is_active': next})
          .eq('id', id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        program['is_active'] = active;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.programsLoadError(e))));
    }
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
                          appStrings.manageProgramsTitle.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _ProgramsText.title.copyWith(
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
                22 + MediaQuery.of(context).viewInsets.bottom,
              ),
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  style: _ProgramsText.body.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: _programsInput(
                    context,
                    appStrings.programName,
                    Icons.grid_view_rounded,
                  ),
                ),
                const SizedBox(height: 12),

                InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt(context),
                      borderRadius: BorderRadius.circular(AppRadii.input),
                      border: Border.all(
                        color: AppColors.border(context),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: _image == null
                        ? const Icon(
                            Icons.image_outlined,
                            size: 30,
                            color: AppColors.accent,
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              _image!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                _ProgramButton(
                  label: appStrings.createProgram,
                  loading: _saving,
                  enabled: _name.text.trim().isNotEmpty,
                  onPressed: _create,
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  )
                else if (_programs.isEmpty)
                  Text(appStrings.noProgramsYet, style: _ProgramsText.subtle)
                else
                  ..._programs.map((program) {
                    final active = program['is_active'] == true;
                    final workoutCount =
                        ((program['workouts'] as List?)?.firstOrNull
                            as Map<String, dynamic>?)?['count'] ??
                        0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: AppColors.surface(context),
                        borderRadius: BorderRadius.circular(AppRadii.input),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () => _updateProgramImage(program),
                                borderRadius: BorderRadius.circular(10),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child:
                                      (program['image_url']
                                              ?.toString()
                                              .isNotEmpty ??
                                          false)
                                      ? Image.network(
                                          program['image_url'].toString(),
                                          width: 54,
                                          height: 54,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 54,
                                          height: 54,
                                          color: AppColors.surfaceAlt(context),
                                          child: const Icon(
                                            Icons.image_outlined,
                                            color: AppColors.accent,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      program['name']?.toString() ??
                                          appStrings.workoutProgram,
                                      style: _ProgramsText.rowTitle.copyWith(
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$workoutCount ${workoutCount == 1 ? appStrings.workoutFallbackTitle : appStrings.workoutsTitle}',
                                      style: _ProgramsText.subtle.copyWith(
                                        color: AppColors.textSecondary(context),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      active
                                          ? appStrings.active
                                          : appStrings.inactive,
                                      style: _ProgramsText.subtle.copyWith(
                                        color: active
                                            ? AppColors.accent
                                            : AppColors.textSecondary(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.more_horiz,
                                  color: AppColors.accent,
                                  size: 24,
                                ),
                                onPressed: () => _showProgramOptions(program),
                              ),
                              Switch(
                                value: active,
                                activeThumbColor: AppColors.accent,
                                onChanged: (_) => _toggle(program),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _programsInput(
  BuildContext context,
  String hint,
  IconData icon,
) {
  return InputDecoration(
    hintText: hint,
    labelText: null,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    hintStyle: _ProgramsText.subtle.copyWith(
      color: AppColors.textSecondary(context),
    ),
    labelStyle: _ProgramsText.subtle.copyWith(
      color: AppColors.textSecondary(context),
    ),
    prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
    filled: true,
    fillColor: AppColors.surfaceAlt(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: BorderSide(color: AppColors.border(context), width: 1),
    ),
  );
}

class _ProgramSheetAction extends StatelessWidget {
  const _ProgramSheetAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary(context);

    return Material(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: danger ? AppColors.danger : AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: _ProgramsText.rowTitle.copyWith(color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _ProgramsText.subtle.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
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

class _ProgramDangerButton extends StatelessWidget {
  const _ProgramDangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: AppColors.background(context),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
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

class _ProgramSecondaryButton extends StatelessWidget {
  const _ProgramSecondaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary(context),
          side: BorderSide(color: AppColors.border(context)),
          backgroundColor: AppColors.surfaceAlt(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
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

class _ProgramButton extends StatelessWidget {
  const _ProgramButton({
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
          backgroundColor: AppColors.accent,
          disabledBackgroundColor: AppColors.surfaceAlt(context),
          foregroundColor: AppColors.background(context),
          disabledForegroundColor: AppColors.textSecondary(context),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.background(context),
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

class _ProgramsText {
  const _ProgramsText._();

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
