import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
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
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF323232), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.workoutEdit.toUpperCase(),
                    style: _ProgramsText.title.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    cursorColor: const Color(0xFFB59B6A),
                    style: _ProgramsText.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _programsInput(
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
                          label: appStrings.workoutSaveChanges,
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
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF323232), width: 1),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.workoutOptions.toUpperCase(),
                    style: _ProgramsText.title,
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
                ],
              ),
            ),
          ),
        );
      },
    );
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
                          appStrings.manageProgramsTitle.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _ProgramsText.title.copyWith(
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
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    style: _ProgramsText.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: const Color(0xFFB59B6A),
                    decoration: _programsInput(
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
                        color: const Color(0xFF171717),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Color(0xFF323232), width: 1),
                      ),
                      alignment: Alignment.center,
                      child: _image == null
                          ? const Icon(
                              Icons.image_outlined,
                              size: 30,
                              color: Color(0xFFB59B6A),
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
                        child: CircularProgressIndicator(
                          color: Color(0xFFB59B6A),
                        ),
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
                          color: const Color(0xFF171717),
                          borderRadius: BorderRadius.circular(10),
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
                                            color: const Color(0xFF252525),
                                            child: const Icon(
                                              Icons.image_outlined,
                                              color: Color(0xFFB59B6A),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        program['name']?.toString() ??
                                            appStrings.workoutProgram,
                                        style: _ProgramsText.rowTitle,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$workoutCount ${workoutCount == 1 ? appStrings.workoutFallbackTitle : appStrings.workoutsTitle}',
                                        style: _ProgramsText.subtle,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        active
                                            ? appStrings.active
                                            : appStrings.inactive,
                                        style: _ProgramsText.subtle.copyWith(
                                          color: active
                                              ? const Color(0xFFB59B6A)
                                              : const Color(0xFFABABAB),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.more_horiz,
                                    color: Color(0xFFB59B6A),
                                    size: 24,
                                  ),
                                  onPressed: () => _showProgramOptions(program),
                                ),
                                Switch(
                                  value: active,
                                  activeThumbColor: const Color(0xFFB59B6A),
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
          ),
        ],
      ),
    );
  }
}

InputDecoration _programsInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: null,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    hintStyle: _ProgramsText.subtle,
    labelStyle: _ProgramsText.subtle,
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
    final color = danger ? const Color(0xFFB42318) : const Color(0xFFB59B6A);

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
              Icon(icon, color: color, size: 20),
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
                      style: _ProgramsText.subtle,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFABABAB)),
            ],
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
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF323232)),
          backgroundColor: const Color(0xFF171717),
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
