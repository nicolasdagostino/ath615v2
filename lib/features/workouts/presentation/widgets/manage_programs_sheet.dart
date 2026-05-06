import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_card.dart';
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
          .select('id, name, is_active')
          .eq('gym_id', widget.gymId)
          .order('name');

      if (!mounted) return;
      setState(() => _programs = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Programs load error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      await widget.client.from('programs').insert({
        'gym_id': widget.gymId,
        'name': name,
      });

      _name.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create program error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> program) async {
    final id = program['id'].toString();
    final active = program['is_active'] == true;

    await widget.client
        .from('programs')
        .update({'is_active': !active})
        .eq('id', id);

    await _load();
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
                appStrings.manageProgramsTitle,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0E0E11),
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: appStrings.programName,
                  hintText: 'CrossFit, Hyrox, Funcional...',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              AppButton(
                label: appStrings.createProgram,
                loading: _saving,
                onPressed: _create,
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: CircularProgressIndicator(color: Color(0xFFB59B6A)))
              else if (_programs.isEmpty)
                Text(appStrings.noProgramsYet)
              else
                ..._programs.map((program) {
                  final active = program['is_active'] == true;
                  return AppCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(
                        program['name']?.toString() ?? appStrings.workoutProgram,
                      ),
                      subtitle: Text(
                        active ? appStrings.active : appStrings.inactive,
                      ),
                      trailing: Switch(
                        value: active,
                        onChanged: (_) => _toggle(program),
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
