import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_centered_loading_indicator.dart';
import '../../../../core/widgets/app_detail_header.dart';
import '../../../../core/widgets/app_form_visuals.dart';
import '../../../../core/widgets/app_large_form_sheet.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';
import '../../data/gym_documents_repository.dart';

class GymDocumentsScreen extends StatefulWidget {
  const GymDocumentsScreen({super.key, this.admin = false, this.repository});
  final bool admin;
  final GymDocumentsRepository? repository;

  @override
  State<GymDocumentsScreen> createState() => _GymDocumentsScreenState();
}

class _GymDocumentsScreenState extends State<GymDocumentsScreen> {
  late final GymDocumentsRepository _repository =
      widget.repository ??
      SupabaseGymDocumentsRepository(Supabase.instance.client);
  List<GymDocument>? _documents;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = widget.admin
          ? await _repository.listAdmin()
          : await _repository.listPublished();
      if (mounted) {
        setState(() {
          _documents = rows;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _documents = const [];
          _error = error;
        });
      }
    }
  }

  Future<void> _edit({GymDocument? document, bool newVersion = false}) async {
    GymDocument? draft = document;
    if (newVersion && document != null) {
      final id = await _repository.createVersion(document.id);
      await _load();
      draft = _documents!.firstWhere((item) => item.versionId == id);
    }
    if (!mounted) return;
    await showAppLargeFormSheet<void>(
      context: context,
      builder: (_) => _DocumentEditor(repository: _repository, document: draft),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background(context),
    body: Column(
        children: [
          AppDetailHeader(
            title: appStrings.documents,
            onBack: () => Navigator.of(context).maybePop(),
            leadingColor: AppColors.primary,
          ),
          Expanded(
            child: _documents == null
                ? const AppCenteredLoadingIndicator(color: AppColors.primary)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenX,
                        AppSpacing.sm,
                        AppSpacing.screenX,
                        AppSpacing.xl,
                      ),
                      children: [
                        if (widget.admin)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const ValueKey('add-gym-document'),
                              onPressed: () => _edit(),
                              icon: const Icon(Icons.add_rounded),
                              label: Text(appStrings.addDocument.toUpperCase()),
                            ),
                          ),
                        if (_error != null)
                          _Message(text: appStrings.documentsLoadError)
                        else if (_documents!.isEmpty)
                          _Message(text: appStrings.noDocuments)
                        else
                          for (final document in _documents!)
                            _DocumentRow(
                              document: document,
                              admin: widget.admin,
                              repository: _repository,
                              onChanged: _load,
                              onEdit: () => _edit(document: document),
                              onNewVersion: () =>
                                  _edit(document: document, newVersion: true),
                            ),
                      ],
                    ),
                  ),
          ),
        ],
    ),
  );
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.admin,
    required this.repository,
    required this.onChanged,
    required this.onEdit,
    required this.onNewVersion,
  });
  final GymDocument document;
  final bool admin;
  final GymDocumentsRepository repository;
  final Future<void> Function() onChanged;
  final VoidCallback onEdit;
  final VoidCallback onNewVersion;

  Future<void> _open(BuildContext context) async {
    await showAppLargeFormSheet<void>(
      context: context,
      builder: (_) =>
          _DocumentViewer(document: document, repository: repository),
    );
    await onChanged();
  }

  Future<void> _archive(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appStrings.archiveDocument),
        content: Text(appStrings.archiveDocumentWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(appStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(appStrings.archiveDocument),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.archive(document.id);
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final publishedAt = DateTime.tryParse(document.publishedAt ?? '');
    final state = admin
        ? (document.documentStatus == 'archived'
              ? appStrings.archived
              : document.status == 'draft'
              ? appStrings.draft
              : appStrings.published)
        : document.required
        ? (document.accepted ? appStrings.accepted : appStrings.pending)
        : appStrings.informational;
    return InkWell(
      key: ValueKey('gym-document-${document.id}-${document.versionId}'),
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(
              document.accepted
                  ? Icons.check_circle_outline
                  : Icons.description_outlined,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(document.title, style: AppTypography.itemTitle(context)),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${document.required ? appStrings.requiredDocument : appStrings.informational} · '
                    '${appStrings.documentVersion(document.versionNumber.toString())} · $state',
                    style: AppTypography.bodySecondary(context),
                  ),
                  if (document.publishedAt != null)
                    Text(
                      appStrings.publishedOn(
                        publishedAt == null
                            ? document.publishedAt!
                            : MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(publishedAt.toLocal()),
                      ),
                      style: AppTypography.helper(context),
                    ),
                  if (!admin && document.acceptedAt != null)
                    Text(
                      appStrings.documentAcceptedOn(
                        _localizedDate(context, document.acceptedAt!),
                      ),
                      style: AppTypography.helper(context),
                    ),
                ],
              ),
            ),
            if (admin)
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') onEdit();
                  if (value == 'version') onNewVersion();
                  if (value == 'archive') {
                    if (context.mounted) await _archive(context);
                  }
                  if (value == 'delete') {
                    await repository.deleteDraft(document.versionId!);
                    await onChanged();
                  }
                },
                itemBuilder: (_) => [
                  if (document.status == 'draft')
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(appStrings.editDocument),
                    ),
                  if (document.status == 'draft')
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(appStrings.deleteDraft),
                    ),
                  if (document.status == 'published')
                    PopupMenuItem(
                      value: 'version',
                      child: Text(appStrings.newVersion),
                    ),
                  if (document.documentStatus != 'archived')
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(appStrings.archiveDocument),
                    ),
                ],
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _DocumentViewer extends StatefulWidget {
  const _DocumentViewer({required this.document, required this.repository});
  final GymDocument document;
  final GymDocumentsRepository repository;
  @override
  State<_DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<_DocumentViewer> {
  bool _accepted = false;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _accepted = widget.document.accepted;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      children: [
        AppSecondaryActionHeader(
          title: widget.document.title,
          leadingIcon: Icons.close_rounded,
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenX),
            children: [
              Text(
                appStrings.documentVersion(
                  widget.document.versionNumber.toString(),
                ),
                style: AppTypography.bodySecondary(context),
              ),
              const SizedBox(height: AppSpacing.md),
              SelectableText(
                widget.document.body,
                style: AppTypography.body(context),
              ),
              if (widget.document.required) ...[
                const SizedBox(height: AppSpacing.lg),
                if (_accepted)
                  Text(
                    widget.document.acceptedAt == null
                        ? appStrings.documentAccepted
                        : appStrings.documentAcceptedOn(
                            _localizedDate(
                              context,
                              widget.document.acceptedAt!,
                            ),
                          ),
                    style: AppTypography.body(
                      context,
                    ).copyWith(color: AppColors.primary),
                  )
                else
                  AppFormSubmitButton(
                    label: appStrings.acceptDocument,
                    loading: _saving,
                    enabled: !_saving,
                    accentColor: AppColors.primary,
                    onPressed: () async {
                      setState(() => _saving = true);
                      await widget.repository.accept(
                        widget.document.versionId!,
                      );
                      if (mounted) {
                        setState(() {
                          _saving = false;
                          _accepted = true;
                        });
                      }
                    },
                  ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _DocumentEditor extends StatefulWidget {
  const _DocumentEditor({required this.repository, this.document});
  final GymDocumentsRepository repository;
  final GymDocument? document;
  @override
  State<_DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<_DocumentEditor> {
  late final _title = TextEditingController(text: widget.document?.title);
  late final _body = TextEditingController(text: widget.document?.body);
  late String _mode = widget.document?.acceptanceMode ?? 'required';
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<String?> _save() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = appStrings.documentFieldsRequired);
      return null;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.document == null) {
        return widget.repository.create(
          title: _title.text,
          body: _body.text,
          mode: _mode,
        );
      }
      await widget.repository.updateDraft(
        widget.document!.versionId!,
        title: _title.text,
        body: _body.text,
        mode: _mode,
      );
      return widget.document!.versionId;
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = appStrings.documentSaveError;
        });
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      children: [
        AppSecondaryActionHeader(
          title: widget.document == null
              ? appStrings.addDocument
              : appStrings.editDocument,
          leadingIcon: Icons.close_rounded,
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppSpacing.screenX),
            children: [
              TextField(
                controller: _title,
                maxLength: 160,
                decoration: InputDecoration(
                  labelText: appStrings.documentTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _body,
                minLines: 8,
                maxLines: 16,
                decoration: InputDecoration(
                  labelText: appStrings.documentContent,
                ),
                maxLength: 20000,
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'required',
                    label: Text(appStrings.requiredDocument),
                  ),
                  ButtonSegment(
                    value: 'informational',
                    label: Text(appStrings.informational),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.single),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                Text(_error!, style: AppTypography.error(context)),
                const SizedBox(height: AppSpacing.sm),
              ],
              AppFormSubmitButton(
                label: appStrings.saveDraft,
                loading: _saving,
                enabled: !_saving,
                accentColor: AppColors.primary,
                onPressed: () async {
                  final id = await _save();
                  if (!context.mounted) return;
                  if (id != null) Navigator.of(context).pop();
                },
              ),
              if (widget.document != null) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          final id = await _save();
                          if (id == null || !context.mounted) return;
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(appStrings.publishDocument),
                              content: Text(appStrings.publishDocumentWarning),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(appStrings.cancel),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(appStrings.publish),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await widget.repository.publish(id);
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          }
                        },
                  child: Text(appStrings.publishDocument.toUpperCase()),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.bodySecondary(context),
      ),
    ),
  );
}

String _localizedDate(BuildContext context, String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return MaterialLocalizations.of(context).formatMediumDate(parsed.toLocal());
}

class MemberDocumentsSection extends StatelessWidget {
  const MemberDocumentsSection({
    super.key,
    required this.memberUserId,
    this.repository,
  });
  final String memberUserId;
  final GymDocumentsRepository? repository;

  @override
  Widget build(BuildContext context) {
    final source =
        repository ?? SupabaseGymDocumentsRepository(Supabase.instance.client);
    return FutureBuilder<List<GymDocument>>(
      future: source.memberStatus(memberUserId),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appStrings.documents.toUpperCase(),
              style: AppTypography.body(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (snapshot.connectionState != ConnectionState.done)
              const LinearProgressIndicator(color: AppColors.primary)
            else if (rows.isEmpty)
              Text(
                appStrings.noDocuments,
                style: AppTypography.bodySecondary(context),
              )
            else
              for (final document in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(
                        document.accepted
                            ? Icons.check_circle_outline
                            : Icons.schedule_rounded,
                        color: document.accepted
                            ? AppColors.primary
                            : AppColors.textSecondary(context),
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              document.title,
                              style: AppTypography.body(context),
                            ),
                            Text(
                              document.outdated
                                  ? appStrings.outdatedDocumentAcceptance(
                                      document.previousAcceptedVersionNumber,
                                      document.previousAcceptedAt == null
                                          ? null
                                          : _localizedDate(
                                              context,
                                              document.previousAcceptedAt!,
                                            ),
                                    )
                                  : document.accepted
                                  ? '${appStrings.accepted} · ${appStrings.documentVersion(document.versionNumber.toString())}'
                                  : appStrings.pending,
                              style: AppTypography.bodySecondary(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}
