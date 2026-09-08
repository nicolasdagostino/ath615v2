import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_admin_actions.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_keyboard_dismissible.dart';
import '../../../../core/widgets/app_pickers.dart';
import '../../data/membership_operations_repository.dart';

enum MembershipAdminOperation { changeExpiration, voidMembership, cancel }

List<MembershipAdminOperation> membershipOperationsForStatus(String status) =>
    switch (status) {
      'active' || 'scheduled' || 'exhausted' => const [
        MembershipAdminOperation.changeExpiration,
        MembershipAdminOperation.voidMembership,
        MembershipAdminOperation.cancel,
      ],
      'expired' => const [
        MembershipAdminOperation.changeExpiration,
        MembershipAdminOperation.voidMembership,
      ],
      _ => const [],
    };

String membershipOperationError(Object error) {
  final value = error.toString();
  if (value.contains('membership_has_usage')) {
    return appStrings.pick(
      'This membership cannot be voided because attendance or a no-show has already been recorded.',
      'Esta membresía no se puede anular porque ya tiene una asistencia o ausencia registrada.',
    );
  }
  if (value.contains('future_bookings_conflict')) {
    return appStrings.pick(
      'There are future bookings after the new expiration date.',
      'Hay reservas futuras posteriores a la nueva fecha de vencimiento.',
    );
  }
  if (value.contains('scheduled_unlimited_chain_conflict')) {
    return appStrings.pick(
      'This Unlimited membership is linked to a later scheduled membership. Its expiration cannot be changed in this version.',
      'Esta membresía Unlimited está encadenada a otra membresía programada. Su vencimiento no se puede cambiar en esta versión.',
    );
  }
  if (value.contains('expiration_must_be_future')) {
    return appStrings.pick(
      'Choose a future date. To finish the membership now, use Cancel membership.',
      'Elige una fecha futura. Para finalizar la membresía ahora, usa Cancelar membresía.',
    );
  }
  if (value.contains('expiration_before_start')) {
    return appStrings.pick(
      'The expiration date must be after the start date.',
      'La fecha de vencimiento debe ser posterior a la fecha de inicio.',
    );
  }
  if (value.contains('membership_terminal')) {
    return appStrings.pick(
      'This membership can no longer be changed.',
      'Esta membresía ya no se puede modificar.',
    );
  }
  return appStrings.pick(
    'We could not update the membership. Please try again.',
    'No pudimos actualizar la membresía. Inténtalo de nuevo.',
  );
}

class MembershipOperationsLauncher extends StatefulWidget {
  const MembershipOperationsLauncher({
    super.key,
    required this.membershipId,
    required this.status,
    required this.dataSource,
    required this.onChanged,
  });

  final String membershipId;
  final String status;
  final MembershipOperationsDataSource dataSource;
  final Future<void> Function() onChanged;

  @override
  State<MembershipOperationsLauncher> createState() =>
      _MembershipOperationsLauncherState();
}

class _MembershipOperationsLauncherState
    extends State<MembershipOperationsLauncher> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final preview = await widget.dataSource.preview(widget.membershipId);
      if (!mounted) return;
      final operations = membershipOperationsForStatus(preview.status);
      if (operations.isEmpty) return;
      setState(() => _loading = false);
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => AppAdminActionSheet(
          accentColor: AppColors.primary,
          onClose: () => Navigator.pop(sheetContext),
          actions: operations
              .map(
                (operation) => AppAdminAction(
                  icon: _icon(operation),
                  label: _label(operation),
                  destructive:
                      operation != MembershipAdminOperation.changeExpiration,
                  onTap: () => _openForm(operation, preview),
                ),
              )
              .toList(),
        ),
      );
    } catch (error) {
      if (mounted) await _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(MembershipAdminOperation operation) => switch (operation) {
    MembershipAdminOperation.changeExpiration => Icons.event_repeat_rounded,
    MembershipAdminOperation.voidMembership => Icons.block_rounded,
    MembershipAdminOperation.cancel => Icons.cancel_outlined,
  };

  String _label(MembershipAdminOperation operation) => switch (operation) {
    MembershipAdminOperation.changeExpiration => appStrings.pick(
      'Change expiration',
      'Cambiar vencimiento',
    ),
    MembershipAdminOperation.voidMembership => appStrings.pick(
      'Void membership',
      'Anular membresía',
    ),
    MembershipAdminOperation.cancel => appStrings.pick(
      'Cancel membership',
      'Cancelar membresía',
    ),
  };

  Future<void> _openForm(
    MembershipAdminOperation operation,
    MembershipOperationPreview preview,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: MembershipOperationForm(
          operation: operation,
          initialPreview: preview,
          dataSource: widget.dataSource,
          onSuccess: () async {
            if (mounted) Navigator.pop(context);
            await widget.onChanged();
          },
        ),
      ),
    );
  }

  Future<void> _showError(Object error) => showAppMessageDialog(
    context: context,
    title: appStrings.pick('Unable to continue', 'No se puede continuar'),
    message: membershipOperationError(error),
    actionLabel: appStrings.pick('OK', 'ACEPTAR'),
    error: true,
  );

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('membership-actions'),
    tooltip: appStrings.pick('Membership actions', 'Acciones de membresía'),
    onPressed: _loading || membershipOperationsForStatus(widget.status).isEmpty
        ? null
        : _open,
    icon: _loading
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.more_horiz_rounded),
    color: AppColors.primary,
  );
}

class MembershipOperationForm extends StatefulWidget {
  const MembershipOperationForm({
    super.key,
    required this.operation,
    required this.initialPreview,
    required this.dataSource,
    required this.onSuccess,
  });

  final MembershipAdminOperation operation;
  final MembershipOperationPreview initialPreview;
  final MembershipOperationsDataSource dataSource;
  final Future<void> Function() onSuccess;

  @override
  State<MembershipOperationForm> createState() =>
      _MembershipOperationFormState();
}

class _MembershipOperationFormState extends State<MembershipOperationForm> {
  final _note = TextEditingController();
  String? _reason;
  DateTime? _newExpiration;
  late MembershipOperationPreview _preview = widget.initialPreview;
  bool _submitting = false;
  bool _previewingDate = false;
  String? _validationError;

  bool get _isExpiration =>
      widget.operation == MembershipAdminOperation.changeExpiration;

  List<(String, String)> get _reasons => switch (widget.operation) {
    MembershipAdminOperation.voidMembership => [
      (
        'assigned_by_mistake',
        appStrings.pick('Assigned by mistake', 'Asignada por error'),
      ),
      (
        'requested_by_mistake',
        appStrings.pick('Requested by mistake', 'Solicitada por error'),
      ),
      ('plan_change', appStrings.pick('Plan change', 'Cambio de plan')),
      ('other', appStrings.pick('Other', 'Otro')),
    ],
    MembershipAdminOperation.cancel => [
      (
        'member_request',
        appStrings.pick('Member request', 'Solicitud del miembro'),
      ),
      ('injury', appStrings.pick('Injury', 'Lesión')),
      ('plan_change', appStrings.pick('Plan change', 'Cambio de plan')),
      ('administrative', appStrings.pick('Administrative', 'Administrativo')),
      ('other', appStrings.pick('Other', 'Otro')),
    ],
    MembershipAdminOperation.changeExpiration => [
      ('injury', appStrings.pick('Injury', 'Lesión')),
      ('gym_closure', appStrings.pick('Gym closure', 'Cierre del gimnasio')),
      (
        'commercial_extension',
        appStrings.pick(
          'Commercial extension / courtesy',
          'Extensión comercial / cortesía',
        ),
      ),
      (
        'administrative_correction',
        appStrings.pick(
          'Administrative correction',
          'Corrección administrativa',
        ),
      ),
      ('other', appStrings.pick('Other', 'Otro')),
    ],
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _date(DateTime? date) => date == null
      ? '—'
      : DateFormat(
          'd MMM yyyy',
          Localizations.localeOf(context).languageCode,
        ).format(date);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate:
          _newExpiration ??
          (_preview.expiresAt?.isAfter(now) == true
              ? _preview.expiresAt!
              : now.add(const Duration(days: 1))),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    final expiration = DateTime(
      picked.year,
      picked.month,
      picked.day,
      23,
      59,
      59,
    );
    setState(() {
      _newExpiration = expiration;
      _previewingDate = true;
      _validationError = null;
    });
    try {
      final preview = await widget.dataSource.preview(
        widget.initialPreview.membershipId,
        newExpiration: expiration,
      );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) {
        setState(() => _validationError = membershipOperationError(error));
      }
    } finally {
      if (mounted) setState(() => _previewingDate = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_reason == null) {
      setState(
        () => _validationError = appStrings.pick(
          'Select a reason.',
          'Selecciona un motivo.',
        ),
      );
      return;
    }
    if (_reason == 'other' && _note.text.trim().length < 2) {
      setState(
        () => _validationError = appStrings.pick(
          'Add a note for Other.',
          'Añade una nota para Otro.',
        ),
      );
      return;
    }
    if (_isExpiration && _newExpiration == null) {
      setState(
        () => _validationError = appStrings.pick(
          'Choose a new expiration date.',
          'Elige una nueva fecha de vencimiento.',
        ),
      );
      return;
    }
    if (widget.operation == MembershipAdminOperation.voidMembership &&
        _preview.hasRecordedUsage) {
      setState(
        () => _validationError = membershipOperationError(
          Exception('membership_has_usage'),
        ),
      );
      return;
    }
    if (_isExpiration && _preview.hasChainedUnlimited) {
      setState(
        () => _validationError = membershipOperationError(
          Exception('scheduled_unlimited_chain_conflict'),
        ),
      );
      return;
    }

    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: _confirmationTitle,
      message: _confirmationMessage,
      confirmLabel: appStrings.pick('CONFIRM', 'CONFIRMAR'),
      cancelLabel: appStrings.pick('BACK', 'VOLVER'),
      destructive:
          widget.operation != MembershipAdminOperation.changeExpiration,
      icon: _isExpiration
          ? Icons.event_repeat_rounded
          : Icons.warning_amber_rounded,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _submitting = true;
      _validationError = null;
    });
    try {
      switch (widget.operation) {
        case MembershipAdminOperation.voidMembership:
          await widget.dataSource.voidMembership(
            membershipId: _preview.membershipId,
            reason: _reason!,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
          break;
        case MembershipAdminOperation.cancel:
          await widget.dataSource.cancelMembership(
            membershipId: _preview.membershipId,
            reason: _reason!,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
          break;
        case MembershipAdminOperation.changeExpiration:
          await widget.dataSource.changeExpiration(
            membershipId: _preview.membershipId,
            newExpiration: _newExpiration!,
            reason: _reason!,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            cancelConflictingBookings: _preview.conflictingBookingCount > 0,
          );
          break;
      }
      if (!mounted) return;
      await widget.onSuccess();
    } catch (error) {
      if (mounted) {
        setState(() => _validationError = membershipOperationError(error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String get _confirmationTitle => switch (widget.operation) {
    MembershipAdminOperation.voidMembership => appStrings.pick(
      'Void membership?',
      '¿Anular membresía?',
    ),
    MembershipAdminOperation.cancel => appStrings.pick(
      'Cancel membership?',
      '¿Cancelar membresía?',
    ),
    MembershipAdminOperation.changeExpiration => appStrings.pick(
      'Change expiration?',
      '¿Cambiar vencimiento?',
    ),
  };

  String get _confirmationMessage {
    if (_isExpiration) {
      final bookings = _preview.conflictingBookingCount;
      final reactivation = _preview.status == 'expired'
          ? appStrings.pick(
              ' This explicitly reactivates the expired membership when credits remain.',
              ' Esto reactiva explícitamente la membresía vencida cuando queden créditos.',
            )
          : '';
      return appStrings.pick(
        'The expiration will change from ${_date(_preview.expiresAt)} to ${_date(_newExpiration)}. $bookings future booking(s) will be cancelled.$reactivation',
        'El vencimiento cambiará de ${_date(_preview.expiresAt)} a ${_date(_newExpiration)}. Se cancelarán $bookings reserva(s) futuras.$reactivation',
      );
    }
    return appStrings.pick(
      '${_preview.futureBookedCount} future booking(s) will be cancelled. Credits are not transferred and financial refunds are not changed.',
      'Se cancelarán ${_preview.futureBookedCount} reserva(s) futuras. Los créditos no se transfieren y los reembolsos financieros no cambian.',
    );
  }

  @override
  Widget build(BuildContext context) => AppKeyboardDismissible(
    child: Material(
      color: AppColors.surface(context),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      child: ListView(
        key: const ValueKey('membership-operation-form'),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.lg,
          AppSpacing.screenX,
          AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Text(
            _confirmationTitle.toUpperCase(),
            style: AppTypography.itemTitle(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ImpactSummary(preview: _preview),
          if (_isExpiration) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              appStrings.pick(
                'Current expiration: ${_date(_preview.expiresAt)}',
                'Vencimiento actual: ${_date(_preview.expiresAt)}',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('membership-expiration-picker'),
              onPressed: _previewingDate ? null : _pickDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(
                _newExpiration == null
                    ? appStrings.pick('CHOOSE NEW DATE', 'ELEGIR NUEVA FECHA')
                    : _date(_newExpiration),
              ),
            ),
            if (_preview.status == 'expired')
              _WarningText(
                key: const ValueKey('membership-reactivation-warning'),
                text: appStrings.pick(
                  'A future date is an explicit administrative reactivation. A pack with no credits remains exhausted.',
                  'Una fecha futura es una reactivación administrativa explícita. Un pack sin créditos permanece agotado.',
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const ValueKey('membership-operation-reason'),
            isExpanded: true,
            initialValue: _reason,
            decoration: InputDecoration(
              labelText: appStrings.pick('Reason', 'Motivo'),
            ),
            items: _reasons
                .map(
                  (reason) => DropdownMenuItem(
                    value: reason.$1,
                    child: Text(reason.$2),
                  ),
                )
                .toList(),
            onChanged: _submitting
                ? null
                : (value) => setState(() {
                    _reason = value;
                    _validationError = null;
                  }),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('membership-operation-note'),
            controller: _note,
            enabled: !_submitting,
            maxLength: 1000,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: appStrings.pick(
                'Administrative note',
                'Nota administrativa',
              ),
            ),
          ),
          if (_preview.futureBookings.isNotEmpty) ...[
            Text(
              appStrings.pick('Bookings affected', 'Reservas afectadas'),
              style: AppTypography.sectionTitle(context),
            ),
            ..._preview.futureBookings.map(
              (booking) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.event_busy_rounded,
                  color: AppColors.danger,
                ),
                title: Text(booking.title),
                subtitle: Text(_date(booking.startsAt)),
              ),
            ),
          ],
          if (_validationError != null)
            _WarningText(
              key: const ValueKey('membership-operation-error'),
              text: _validationError!,
            ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const ValueKey('membership-operation-submit'),
            onPressed: _submitting || _previewingDate ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor:
                  widget.operation == MembershipAdminOperation.changeExpiration
                  ? AppColors.primary
                  : AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(AppSizes.minimumTouchTarget),
            ),
            child: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(appStrings.pick('CONTINUE', 'CONTINUAR')),
          ),
        ],
      ),
    ),
  );
}

class _ImpactSummary extends StatelessWidget {
  const _ImpactSummary({required this.preview});
  final MembershipOperationPreview preview;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('membership-impact-preview'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt(context),
      borderRadius: BorderRadius.circular(AppRadii.input),
      border: Border.all(color: AppColors.border(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          preview.planName.toUpperCase(),
          style: AppTypography.itemTitle(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          appStrings.pick(
            'Credits: ${preview.creditsRemaining ?? '∞'} / ${preview.creditsTotal ?? '∞'}',
            'Créditos: ${preview.creditsRemaining ?? '∞'} / ${preview.creditsTotal ?? '∞'}',
          ),
        ),
        Text(
          appStrings.pick(
            'Attendance: ${preview.attendedCount}',
            'Asistencias: ${preview.attendedCount}',
          ),
        ),
        Text(
          appStrings.pick(
            'No-shows: ${preview.noShowCount}',
            'Ausencias: ${preview.noShowCount}',
          ),
        ),
        Text(
          appStrings.pick(
            'Future bookings: ${preview.futureBookedCount}',
            'Reservas futuras: ${preview.futureBookedCount}',
          ),
        ),
      ],
    ),
  );
}

class _WarningText extends StatelessWidget {
  const _WarningText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      text,
      style: AppTypography.bodySecondary(
        context,
      ).copyWith(color: AppColors.danger),
    ),
  );
}
