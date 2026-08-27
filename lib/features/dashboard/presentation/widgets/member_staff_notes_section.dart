import 'package:flutter/material.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_large_form_sheet.dart';
import '../../data/member_staff_notes_repository.dart';

class MemberStaffNotesSection extends StatefulWidget {
  const MemberStaffNotesSection({
    super.key,
    required this.memberUserId,
    required this.repository,
    required this.canManage,
  });

  final String memberUserId;
  final MemberStaffNotesRepository repository;
  final bool canManage;

  @override
  State<MemberStaffNotesSection> createState() =>
      _MemberStaffNotesSectionState();
}

class _MemberStaffNotesSectionState extends State<MemberStaffNotesSection> {
  late Future<List<MemberStaffNote>> _notes = _load();

  Future<List<MemberStaffNote>> _load() =>
      widget.repository.listForMember(widget.memberUserId);

  void _reload() => setState(() {
    _notes = _load();
  });

  Future<void> _edit([MemberStaffNote? note]) async {
    final changed = await showAppLargeFormSheet<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _MemberStaffNoteEditor(
        memberUserId: widget.memberUserId,
        repository: widget.repository,
        note: note,
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _delete(MemberStaffNote note) async {
    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: appStrings.deleteInternalNote,
      message: appStrings.deleteInternalNoteConfirmation,
      confirmLabel: appStrings.delete,
      cancelLabel: appStrings.cancel,
    );
    if (!confirmed) return;
    try {
      await widget.repository.delete(note.id);
      if (mounted) _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.internalNoteSaveError)));
    }
  }

  Future<void> _togglePinned(MemberStaffNote note) async {
    try {
      await widget.repository.save(
        memberUserId: widget.memberUserId,
        body: note.body,
        isPinned: !note.isPinned,
        noteId: note.id,
      );
      if (mounted) _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.internalNoteSaveError)));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('member-staff-notes-section'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              appStrings.internalNotes.toUpperCase(),
              style: AppTypography.sectionTitle(context),
            ),
          ),
          if (widget.canManage)
            TextButton.icon(
              key: const ValueKey('add-member-staff-note'),
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(appStrings.addNote.toUpperCase()),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        appStrings.internalNotesStaffOnly,
        style: AppTypography.helper(context),
      ),
      const SizedBox(height: AppSpacing.sm),
      FutureBuilder<List<MemberStaffNote>>(
        future: _notes,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return TextButton(
              onPressed: _reload,
              child: Text(appStrings.retry),
            );
          }
          final notes = snapshot.data ?? const <MemberStaffNote>[];
          if (notes.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                appStrings.noInternalNotes,
                key: const ValueKey('member-staff-notes-empty'),
                style: AppTypography.bodySecondary(context),
              ),
            );
          }
          return Column(
            children: [
              for (final note in notes)
                _MemberStaffNoteRow(
                  note: note,
                  canManage: widget.canManage,
                  onEdit: () => _edit(note),
                  onTogglePinned: () => _togglePinned(note),
                  onDelete: () => _delete(note),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _MemberStaffNoteRow extends StatelessWidget {
  const _MemberStaffNoteRow({
    required this.note,
    required this.canManage,
    required this.onEdit,
    required this.onTogglePinned,
    required this.onDelete,
  });

  final MemberStaffNote note;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onTogglePinned;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(note.updatedAt);
    return Container(
      key: ValueKey('member-staff-note-${note.id}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: .7),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            note.isPinned ? Icons.flag_rounded : Icons.sticky_note_2_outlined,
            size: 18,
            color: note.isPinned
                ? AppColors.primary
                : AppColors.textSecondary(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.body, style: AppTypography.body(context)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${note.authorName} · $date',
                  style: AppTypography.helper(context),
                ),
              ],
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              tooltip: appStrings.actions,
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'pin') onTogglePinned();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(appStrings.editNote)),
                PopupMenuItem(
                  value: 'pin',
                  child: Text(
                    note.isPinned
                        ? appStrings.removeFromImportant
                        : appStrings.markAsImportant,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(appStrings.deleteInternalNote),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MemberStaffNoteEditor extends StatefulWidget {
  const _MemberStaffNoteEditor({
    required this.memberUserId,
    required this.repository,
    this.note,
  });

  final String memberUserId;
  final MemberStaffNotesRepository repository;
  final MemberStaffNote? note;

  @override
  State<_MemberStaffNoteEditor> createState() => _MemberStaffNoteEditorState();
}

class _MemberStaffNoteEditorState extends State<_MemberStaffNoteEditor> {
  late final TextEditingController _body = TextEditingController(
    text: widget.note?.body ?? '',
  );
  late bool _isPinned = widget.note?.isPinned ?? false;
  bool _saving = false;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _body.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty || body.length > 2000) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.save(
        memberUserId: widget.memberUserId,
        body: body,
        isPinned: _isPinned,
        noteId: widget.note?.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.internalNoteSaveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        _body.text.trim().isNotEmpty && _body.text.trim().length <= 2000;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(58),
        child: AppFormHeader(
          title: widget.note == null ? appStrings.addNote : appStrings.editNote,
          onClose: () => Navigator.of(context).pop(),
          accentColor: AppColors.primary,
        ),
      ),
      resizeToAvoidBottomInset: false,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.md,
          AppSpacing.screenX,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSectionLabel(label: appStrings.internalNotes),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: TextField(
                key: const ValueKey('member-staff-note-body'),
                controller: _body,
                focusNode: _focusNode,
                expands: true,
                minLines: null,
                maxLines: null,
                maxLength: 2000,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                style: appFormValueStyle(context),
                decoration: appFormInput(
                  context,
                  icon: Icons.sticky_note_2_outlined,
                  accentColor: AppColors.primary,
                  hintText: appStrings.internalNoteHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('member-staff-note-pinned'),
              contentPadding: EdgeInsets.zero,
              value: _isPinned,
              activeTrackColor: AppColors.primary,
              title: Text(
                _isPinned
                    ? appStrings.removeFromImportant
                    : appStrings.markAsImportant,
                style: AppTypography.body(context),
              ),
              onChanged: (value) => setState(() => _isPinned = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppFormSubmitButton(
              key: const ValueKey('save-member-staff-note'),
              label: appStrings.save,
              loading: _saving,
              enabled: valid,
              onPressed: _save,
              accentColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
