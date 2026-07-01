import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';

Future<void> showAttendanceSheet({
  required BuildContext context,
  required SupabaseClient client,
  required Map<String, dynamic> klass,
  required String Function(String raw) formatDateTime,
  required String Function(String status) prettyStatus,
  required bool canMarkAttendance,
  required Future<void> Function() onChanged,
}) async {
  final classId = klass['id'].toString();

  final bookings = await client
      .from('class_bookings')
      .select('id, user_id, status, created_at, guest_name, is_guest')
      .eq('class_id', classId)
      .neq('status', 'cancelled')
      .order('created_at', ascending: true);

  final bookingRows = List<Map<String, dynamic>>.from(bookings);
  final userIds = bookingRows
      .where((b) => b['user_id'] != null)
      .map((b) => b['user_id'].toString())
      .toList();

  final profiles = userIds.isEmpty
      ? <Map<String, dynamic>>[]
      : List<Map<String, dynamic>>.from(
          await client
              .from('profiles')
              .select('id, full_name, email, avatar_url')
              .inFilter('id', userIds),
        );

  final profileById = {for (final p in profiles) p['id'].toString(): p};
  final startsAt = DateTime.parse(klass['starts_at']).toLocal();
  final durationMinutes = klass['duration_minutes'] as int? ?? 60;
  final classFinished = DateTime.now().isAfter(
    startsAt.add(Duration(minutes: durationMinutes)),
  );

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> addGuest() async {
            final capacity = klass['capacity'] as int? ?? 0;
            if (capacity > 0 && bookingRows.length >= capacity) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(appStrings.bookingClassFull)),
              );
              return;
            }

            final controller = TextEditingController();

            final guestName = await showModalBottomSheet<String>(
              context: sheetContext,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (dialogContext) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
                  ),
                  child: SafeArea(
                    child: Container(
                      margin: EdgeInsets.all(AppSpacing.sheetMargin),
                      padding: EdgeInsets.all(AppSpacing.cardPadding),
                      decoration: BoxDecoration(
                        color: AppColors.surface(dialogContext),
                        borderRadius: BorderRadius.circular(AppRadii.sheet),
                        border: Border.all(
                          color: AppColors.border(dialogContext),
                          width: 1,
                        ),
                        boxShadow: AppShadows.card(dialogContext),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          Text(
                            appStrings.addGuest.toUpperCase(),
                            style: _AttendanceText.title.copyWith(
                              color: AppColors.textPrimary(dialogContext),
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            textCapitalization: TextCapitalization.words,
                            cursorColor: AppColors.accent,
                            style: _AttendanceText.rowTitle.copyWith(
                              color: AppColors.textPrimary(dialogContext),
                            ),
                            decoration: InputDecoration(
                              labelText: appStrings.guestName,
                              labelStyle: _AttendanceText.subtle.copyWith(
                                color: AppColors.textSecondary(dialogContext),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppColors.border(dialogContext),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _AttendanceSheetSecondaryButton(
                                  label: appStrings.cancel,
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _AttendanceSheetPrimaryButton(
                                  label: appStrings.addGuest,
                                  onTap: () {
                                    final value = controller.text.trim();
                                    if (value.isEmpty) return;
                                    Navigator.of(dialogContext).pop(value);
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

            if (guestName == null || guestName.trim().isEmpty) return;

            try {
              final inserted = await client
                  .from('class_bookings')
                  .insert({
                    'class_id': classId,
                    'user_id': null,
                    'guest_name': guestName.trim(),
                    'is_guest': true,
                    'status': 'booked',
                  })
                  .select(
                    'id, user_id, status, created_at, guest_name, is_guest',
                  )
                  .single();

              bookingRows.add(Map<String, dynamic>.from(inserted));
              setSheetState(() {});
              await onChanged();
            } catch (e) {
              if (!sheetContext.mounted) return;
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(appStrings.attendanceError(e))),
              );
            }
          }

          Future<void> removeBooking(
            Map<String, dynamic> booking,
            String name,
          ) async {
            final confirmed = await showModalBottomSheet<bool>(
              context: sheetContext,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (dialogContext) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
                  ),
                  child: SafeArea(
                    child: Container(
                      margin: EdgeInsets.all(AppSpacing.sheetMargin),
                      padding: EdgeInsets.all(AppSpacing.cardPadding),
                      decoration: BoxDecoration(
                        color: AppColors.surface(dialogContext),
                        borderRadius: BorderRadius.circular(AppRadii.sheet),
                        border: Border.all(
                          color: AppColors.border(dialogContext),
                          width: 1,
                        ),
                        boxShadow: AppShadows.card(dialogContext),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person_remove_alt_1_rounded,
                                color: AppColors.danger,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  appStrings.removeBooking.toUpperCase(),
                                  style: _AttendanceText.title.copyWith(
                                    color: AppColors.textPrimary(dialogContext),
                                    fontSize: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            name,
                            style: _AttendanceText.rowTitle.copyWith(
                              color: AppColors.textPrimary(dialogContext),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            appStrings.deleteWorkoutMsg,
                            style: _AttendanceText.subtle.copyWith(
                              color: AppColors.textSecondary(dialogContext),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _AttendanceSheetSecondaryButton(
                                  label: appStrings.cancel,
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(false),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _AttendanceSheetDangerButton(
                                  label: appStrings.remove,
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(true),
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
              await client.rpc(
                'admin_cancel_class_booking',
                params: {'p_booking_id': booking['id']},
              );

              try {
                await client.functions.invoke('send-notifications');
              } catch (_) {
                // Notifications are still queued and will be sent by the scheduler.
              }

              bookingRows.removeWhere((b) => b['id'] == booking['id']);
              setSheetState(() {});
              await onChanged();
            } catch (e) {
              if (!sheetContext.mounted) return;
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(appStrings.attendanceError(e))),
              );
            }
          }

          Future<void> finishAttendance() async {
            final pendingCount = bookingRows
                .where((b) => b['status'].toString() == 'booked')
                .length;

            if (pendingCount == 0) return;

            final confirmed = await showModalBottomSheet<bool>(
              context: sheetContext,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (dialogContext) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
                  ),
                  child: SafeArea(
                    child: Container(
                      margin: EdgeInsets.all(AppSpacing.sheetMargin),
                      padding: EdgeInsets.all(AppSpacing.cardPadding),
                      decoration: BoxDecoration(
                        color: AppColors.surface(dialogContext),
                        borderRadius: BorderRadius.circular(AppRadii.sheet),
                        border: Border.all(
                          color: AppColors.border(dialogContext),
                          width: 1,
                        ),
                        boxShadow: AppShadows.card(dialogContext),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.fact_check_rounded,
                                color: AppColors.accent,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  appStrings.finishAttendanceTitle
                                      .toUpperCase(),
                                  style: _AttendanceText.title.copyWith(
                                    color: AppColors.textPrimary(dialogContext),
                                    fontSize: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            appStrings.finishAttendanceMsg,
                            style: _AttendanceText.subtle.copyWith(
                              color: AppColors.textSecondary(dialogContext),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _AttendanceSheetSecondaryButton(
                                  label: appStrings.cancel,
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(false),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _AttendanceSheetPrimaryButton(
                                  label: appStrings.finish,
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(true),
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
              await client
                  .from('class_bookings')
                  .update({'status': 'attended'})
                  .eq('class_id', classId)
                  .eq('status', 'booked');

              for (final booking in bookingRows) {
                if (booking['status'].toString() == 'booked') {
                  booking['status'] = 'attended';
                }
              }

              setSheetState(() {});
              await onChanged();
            } catch (e) {
              if (!sheetContext.mounted) return;
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(appStrings.attendanceError(e))),
              );
            }
          }

          Future<void> updateStatus(
            Map<String, dynamic> booking,
            String status,
          ) async {
            if (!canMarkAttendance) return;

            try {
              await client
                  .from('class_bookings')
                  .update({'status': status})
                  .eq('id', booking['id']);

              booking['status'] = status;
              setSheetState(() {});
              await onChanged();
            } catch (e) {
              if (!sheetContext.mounted) return;
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(appStrings.attendanceError(e))),
              );
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.86,
                ),
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(AppRadii.sheet),
                  border: Border.all(
                    color: AppColors.border(context),
                    width: 1,
                  ),
                ),
                child: ListView(
                  shrinkWrap: false,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            appStrings.attendance.toUpperCase(),
                            style: _AttendanceText.title.copyWith(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ),
                        _AttendanceCountPill(
                          label:
                              '${bookingRows.length} / ${klass['capacity'] as int? ?? 0}',
                        ),
                        const SizedBox(width: 8),
                        _AttendanceAddGuestButton(onTap: addGuest),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (klass['title']?.toString() ?? appStrings.classFallback)
                          .toUpperCase(),
                      style: _AttendanceText.rowTitle.copyWith(
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDateTime(klass['starts_at']),
                      style: _AttendanceText.subtle.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (bookingRows.isEmpty)
                      Text(
                        appStrings.noBookingsYet,
                        style: _AttendanceText.subtle.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      )
                    else
                      ...bookingRows.map((booking) {
                        final isGuest = booking['is_guest'] == true;
                        final profile = isGuest
                            ? null
                            : profileById[booking['user_id'].toString()];
                        final name = isGuest
                            ? 'Guest · ${(booking['guest_name'] ?? appStrings.member).toString()}'
                            : (profile?['full_name'] ??
                                      profile?['email'] ??
                                      appStrings.member)
                                  .toString();
                        final email = isGuest
                            ? ''
                            : (profile?['email'] ?? '').toString();
                        final avatarUrl = isGuest
                            ? null
                            : profile?['avatar_url']?.toString();
                        final status = booking['status'].toString();

                        return _AttendanceMemberCard(
                          name: name,
                          email: email,
                          avatarUrl: avatarUrl,
                          status: prettyStatus(status),
                          selectedStatus: status,
                          canMarkAttendance: canMarkAttendance,
                          onToggleAttended: canMarkAttendance
                              ? () => updateStatus(
                                  booking,
                                  status == 'attended' ? 'booked' : 'attended',
                                )
                              : null,
                          onRemove: () => removeBooking(booking, name),
                        );
                      }),
                    if (classFinished &&
                        bookingRows.any(
                          (b) => b['status'].toString() == 'booked',
                        )) ...[
                      const SizedBox(height: 10),
                      _AttendanceFinishButton(onTap: finishAttendance),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _AttendanceText {
  const _AttendanceText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle section = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.8,
    height: 1,
  );

  static TextStyle rowTitle = GoogleFonts.barlowCondensed(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABABAB),
    letterSpacing: 0.3,
    height: 1,
  );
}

class _AttendanceAddGuestButton extends StatelessWidget {
  const _AttendanceAddGuestButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background(context),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: const Icon(Icons.person_add_alt_1_rounded, size: 20),
      ),
    );
  }
}

class _AttendanceCountPill extends StatelessWidget {
  const _AttendanceCountPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border(context), width: 1),
      ),
      child: Text(
        label,
        style: _AttendanceText.section.copyWith(color: AppColors.accent),
      ),
    );
  }
}

class _AttendanceMemberCard extends StatelessWidget {
  const _AttendanceMemberCard({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.status,
    required this.selectedStatus,
    required this.canMarkAttendance,
    required this.onToggleAttended,
    required this.onRemove,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final String status;
  final String selectedStatus;
  final bool canMarkAttendance;
  final VoidCallback? onToggleAttended;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final attended = selectedStatus == 'attended';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: attended
            ? AppColors.accent.withValues(alpha: 0.08)
            : AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: attended ? AppColors.accent : AppColors.border(context),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _AttendanceAvatar(name: name, avatarUrl: avatarUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _AttendanceText.rowTitle.copyWith(
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AttendanceIconButton(
            icon: Icons.check_rounded,
            selected: attended,
            onTap: onToggleAttended,
          ),
          const SizedBox(width: 6),
          _AttendanceIconButton(
            icon: Icons.close_rounded,
            danger: true,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AttendanceAvatar extends StatelessWidget {
  const _AttendanceAvatar({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        color: AppColors.surface(context),
        child: hasAvatar
            ? Image.network(
                avatarUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              )
            : Text(
                name.trim().isEmpty ? 'M' : name.trim()[0].toUpperCase(),
                style: _AttendanceText.rowTitle.copyWith(
                  color: AppColors.accent,
                ),
              ),
      ),
    );
  }
}

class _AttendanceIconButton extends StatelessWidget {
  const _AttendanceIconButton({
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final background = selected
        ? AppColors.accent
        : danger
        ? AppColors.surface(context)
        : AppColors.surface(context);

    final foreground = selected
        ? AppColors.background(context)
        : disabled
        ? AppColors.textSecondary(context)
        : danger
        ? AppColors.danger
        : AppColors.textPrimary(context);

    return SizedBox(
      width: 32,
      height: 32,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledForegroundColor: AppColors.textSecondary(context),
          side: BorderSide(
            color: selected ? AppColors.accent : AppColors.border(context),
            width: 1,
          ),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _AttendanceSheetSecondaryButton extends StatelessWidget {
  const _AttendanceSheetSecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary(context),
          side: BorderSide(color: AppColors.border(context), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _AttendanceText.rowTitle.copyWith(
            color: AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }
}

class _AttendanceSheetDangerButton extends StatelessWidget {
  const _AttendanceSheetDangerButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _AttendanceText.rowTitle.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _AttendanceFinishButton extends StatelessWidget {
  const _AttendanceFinishButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.fact_check_rounded, size: 18),
        label: Text(appStrings.finishAttendance.toUpperCase()),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _AttendanceSheetPrimaryButton extends StatelessWidget {
  const _AttendanceSheetPrimaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _AttendanceText.rowTitle.copyWith(
            color: AppColors.background(context),
          ),
        ),
      ),
    );
  }
}
