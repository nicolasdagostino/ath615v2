import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_admin_actions.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_large_form_sheet.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';
import '../workout_colors.dart';

Future<void> showManageProgramsSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
}) async {
  await showAppLargeFormSheet<void>(
    context: context,
    builder: (_) => ManageProgramsView(client: client, gymId: gymId),
  );
}

class ManageProgramsView extends StatefulWidget {
  const ManageProgramsView({
    super.key,
    required this.client,
    required this.gymId,
  });

  final SupabaseClient client;
  final String gymId;

  @override
  State<ManageProgramsView> createState() => _ManageProgramsViewState();
}

class _ManageProgramsViewState extends State<ManageProgramsView> {
  bool _loading = true;
  List<Map<String, dynamic>> _programs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.client
          .from('programs')
          .select('id, name, is_active, workouts(count)')
          .eq('gym_id', widget.gymId)
          .order('name');
      if (mounted) {
        setState(() => _programs = List<Map<String, dynamic>>.from(rows));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.programsLoadError(error))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? program]) async {
    final changed = await showAppLargeFormSheet<bool>(
      context: context,
      builder: (_) => ProgramFormView(
        client: widget.client,
        gymId: widget.gymId,
        program: program,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> program) async {
    final id = program['id'].toString();
    final name = program['name']?.toString() ?? appStrings.workoutProgram;
    final count =
        ((program['workouts'] as List?)?.firstOrNull
            as Map<String, dynamic>?)?['count'] ??
        0;
    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: appStrings.deleteProgram,
      message:
          '$name\n$count ${count == 1 ? appStrings.workoutFallbackTitle : appStrings.workoutsTitle}\n\n${appStrings.deleteProgramWarning}',
      confirmLabel: appStrings.delete,
      cancelLabel: appStrings.cancel,
    );
    if (!confirmed) return;
    try {
      await widget.client.from('workouts').delete().eq('program_id', id);
      await widget.client.from('programs').delete().eq('id', id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.programsLoadError(error))),
      );
    }
  }

  Future<void> _toggle(Map<String, dynamic> program) async {
    final current = program['is_active'] == true;
    setState(() => program['is_active'] = !current);
    try {
      await widget.client
          .from('programs')
          .update({'is_active': !current})
          .eq('id', program['id']);
    } catch (error) {
      if (!mounted) return;
      setState(() => program['is_active'] = current);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.programsLoadError(error))),
      );
    }
  }

  void _showActions(Map<String, dynamic> program) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (sheetContext) => AppAdminActionSheet(
        accentColor: WorkoutColors.primary,
        onClose: () => Navigator.pop(sheetContext),
        actions: [
          AppAdminAction(
            icon: Icons.edit_outlined,
            label: appStrings.editProgram,
            onTap: () => _openForm(program),
          ),
          AppAdminAction(
            icon: Icons.delete_outline_rounded,
            label: appStrings.deleteProgram,
            destructive: true,
            onTap: () => _delete(program),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: SafeArea(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AppSecondaryActionHeader(
                onBack: () => Navigator.of(context).pop(),
              ),
              IgnorePointer(
                child: Text(
                  appStrings.manageProgramsTitle.toUpperCase(),
                  key: const ValueKey('programs-title'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const AppCenteredLoadingIndicator(
                    color: WorkoutColors.primary,
                  )
                : _programs.isEmpty
                ? Center(
                    child: Text(
                      appStrings.noProgramsYet,
                      style: AppTypography.bodySecondary(context),
                    ),
                  )
                : ListView.separated(
                    key: const ValueKey('programs-list'),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenX,
                      AppSpacing.md,
                      AppSpacing.screenX,
                      104,
                    ),
                    itemCount: _programs.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: AppColors.border(context)),
                    itemBuilder: (context, index) {
                      final program = _programs[index];
                      final active = program['is_active'] == true;
                      return ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 72),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    program['name']?.toString() ??
                                        appStrings.workoutProgram,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.itemTitle(context),
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    active
                                        ? appStrings.active
                                        : appStrings.inactive,
                                    style: AppTypography.helper(context)
                                        .copyWith(
                                          color: active
                                              ? WorkoutColors.primary
                                              : AppColors.textSecondary(
                                                  context,
                                                ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            AppOutlinedAdminButton(
                              key: ValueKey('program-edit-${program['id']}'),
                              icon: Icons.edit_outlined,
                              tooltip: appStrings.editProgram,
                              onPressed: () => _showActions(program),
                              accentColor: WorkoutColors.primary,
                            ),
                            Switch(
                              value: active,
                              activeThumbColor: WorkoutColors.primary,
                              onChanged: (_) => _toggle(program),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton(
      key: const ValueKey('program-create'),
      tooltip: appStrings.createProgram,
      onPressed: _openForm,
      backgroundColor: WorkoutColors.primary,
      foregroundColor: Colors.white,
      child: const Icon(Icons.add_rounded),
    ),
  );
}

class ProgramFormView extends StatefulWidget {
  const ProgramFormView({
    super.key,
    required this.client,
    required this.gymId,
    this.program,
  });

  final SupabaseClient client;
  final String gymId;
  final Map<String, dynamic>? program;

  @override
  State<ProgramFormView> createState() => _ProgramFormViewState();
}

class _ProgramFormViewState extends State<ProgramFormView> {
  late final TextEditingController _name;
  bool _saving = false;

  bool get _editing => widget.program != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.program?['name']?.toString());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      if (_editing) {
        await widget.client
            .from('programs')
            .update({'name': name})
            .eq('id', widget.program!['id']);
      } else {
        await widget.client.from('programs').insert({
          'gym_id': widget.gymId,
          'name': name,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.createProgramError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: Column(
      children: [
        AppFormHeader(
          title: _editing ? appStrings.editProgram : appStrings.createProgram,
          onClose: () => Navigator.pop(context),
          accentColor: WorkoutColors.primary,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenX),
            children: [
              AppFormSectionLabel(label: appStrings.programName.toUpperCase()),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                key: const ValueKey('program-name-field'),
                controller: _name,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.words,
                style: appFormValueStyle(context),
                decoration: appFormInput(
                  context,
                  icon: Icons.grid_view_rounded,
                  accentColor: WorkoutColors.primary,
                  hintText: appStrings.programName,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.sm,
          AppSpacing.screenX,
          AppSpacing.md,
        ),
        child: AppFormSubmitButton(
          label: _editing ? appStrings.saveChanges : appStrings.createProgram,
          loading: _saving,
          enabled: _name.text.trim().isNotEmpty,
          onPressed: _save,
          accentColor: WorkoutColors.primary,
        ),
      ),
    ),
  );
}
