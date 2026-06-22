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
      .select('id, user_id, status, created_at')
      .eq('class_id', classId)
      .neq('status', 'cancelled')
      .order('created_at', ascending: true);

  final bookingRows = List<Map<String, dynamic>>.from(bookings);
  final userIds = bookingRows.map((b) => b['user_id'].toString()).toList();

  final profiles = userIds.isEmpty
      ? <Map<String, dynamic>>[]
      : List<Map<String, dynamic>>.from(
          await client
              .from('profiles')
              .select('id, full_name, email, avatar_url')
              .inFilter('id', userIds),
        );

  final profileById = {for (final p in profiles) p['id'].toString(): p};

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
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
                        _AttendanceCountPill(label: '${bookingRows.length}'),
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
                    const SizedBox(height: 12),
                    if (bookingRows.isEmpty)
                      Text(
                        appStrings.noBookingsYet,
                        style: _AttendanceText.subtle.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      )
                    else
                      ...bookingRows.map((booking) {
                        final profile =
                            profileById[booking['user_id'].toString()];
                        final name =
                            (profile?['full_name'] ??
                                    profile?['email'] ??
                                    appStrings.member)
                                .toString();
                        final email = (profile?['email'] ?? '').toString();
                        final avatarUrl = profile?['avatar_url']?.toString();
                        final status = booking['status'].toString();

                        return _AttendanceMemberCard(
                          name: name,
                          email: email,
                          avatarUrl: avatarUrl,
                          status: prettyStatus(status),
                          selectedStatus: status,
                          canMarkAttendance: canMarkAttendance,
                          onAttended: canMarkAttendance
                              ? () => updateStatus(booking, 'attended')
                              : null,
                          onNoShow: canMarkAttendance
                              ? () => updateStatus(booking, 'no_show')
                              : null,
                        );
                      }),
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
    fontSize: 17,
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
    required this.onAttended,
    required this.onNoShow,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final String status;
  final String selectedStatus;
  final bool canMarkAttendance;
  final VoidCallback? onAttended;
  final VoidCallback? onNoShow;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border(context), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _AttendanceAvatar(name: name, avatarUrl: avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _AttendanceText.rowTitle.copyWith(
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _AttendanceText.subtle.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                status.toUpperCase(),
                style: _AttendanceText.subtle.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AttendanceStatusButton(
                  label: appStrings.attended,
                  selected: selectedStatus == 'attended',
                  onTap: onAttended,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AttendanceStatusButton(
                  label: appStrings.noShow,
                  selected: selectedStatus == 'no_show',
                  danger: true,
                  onTap: onNoShow,
                ),
              ),
            ],
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
        width: 42,
        height: 42,
        alignment: Alignment.center,
        color: AppColors.surface(context),
        child: hasAvatar
            ? Image.network(
                avatarUrl!,
                width: 42,
                height: 42,
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

class _AttendanceStatusButton extends StatelessWidget {
  const _AttendanceStatusButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    final background = selected
        ? (danger ? AppColors.danger : AppColors.accent)
        : AppColors.surface(context);

    final foreground = selected
        ? (danger ? Colors.white : AppColors.background(context))
        : disabled
        ? AppColors.textSecondary(context)
        : AppColors.textPrimary(context);

    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: background,
          disabledBackgroundColor: AppColors.surface(context),
          foregroundColor: foreground,
          disabledForegroundColor: AppColors.textSecondary(context),
          side: BorderSide(
            color: selected ? background : AppColors.border(context),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.barlowCondensed(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            height: 1,
          ),
        ),
      ),
    );
  }
}
