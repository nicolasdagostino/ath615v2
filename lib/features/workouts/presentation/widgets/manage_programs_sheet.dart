import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../../../core/widgets/app_button.dart';

Future<void> showManageProgramsSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ManageProgramsSheet(client: client, gymId: gymId),
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
          .select('id, name, is_active, image_url')
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
                appStrings.manageProgramsTitle.toUpperCase(),
                style: _ProgramsText.title,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: _ProgramsText.body,
                decoration: _programsInput(
                  appStrings.programName,
                  Icons.badge_outlined,
                ),
              ),
              const SizedBox(height: 12),

              InkWell(
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F7),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: _image == null
                      ? const Icon(
                          Icons.image_outlined,
                          size: 30,
                          color: Color(0xFF8F96A3),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.file(
                            _image!,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              AppButton(
                label: appStrings.createProgram,
                loading: _saving,
                onPressed: _create,
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFB59B6A)),
                  ),
                )
              else if (_programs.isEmpty)
                Text(appStrings.noProgramsYet, style: _ProgramsText.subtle)
              else
                ..._programs.map((program) {
                  final active = program['is_active'] == true;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => _updateProgramImage(program),
                              borderRadius: BorderRadius.circular(14),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
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
                                        color: const Color(0xFFE8EAF0),
                                        child: const Icon(
                                          Icons.image_outlined,
                                          color: Color(0xFF8F96A3),
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
                                    style: _ProgramsText.rowTitle,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    active
                                        ? appStrings.active
                                        : appStrings.inactive,
                                    style: _ProgramsText.subtle,
                                  ),
                                ],
                              ),
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
    );
  }
}

InputDecoration _programsInput(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    labelText: hint,
    hintStyle: _ProgramsText.subtle,
    labelStyle: _ProgramsText.subtle,
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

class _ProgramsText {
  const _ProgramsText._();

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
