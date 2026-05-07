import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';

Future<void> showAttendanceSheet({
  required BuildContext context,
  required SupabaseClient client,
  required Map<String, dynamic> klass,
  required String Function(String raw) formatDateTime,
  required String Function(String status) prettyStatus,
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
              .select('id, full_name, email')
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
              ScaffoldMessenger.of(
                sheetContext,
              ).showSnackBar(SnackBar(content: Text('Attendance error: $e')));
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
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: ListView(
                  shrinkWrap: false,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD7DAE0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      (klass['title']?.toString() ?? appStrings.classFallback)
                          .toUpperCase(),
                      style: _AttendanceText.title,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatDateTime(klass['starts_at']),
                      style: _AttendanceText.subtle,
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Text('ATTENDANCE', style: _AttendanceText.section),
                        const Spacer(),
                        _AttendanceCountPill(
                          label: '${bookingRows.length}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (bookingRows.isEmpty)
                      Text('No bookings yet.', style: _AttendanceText.subtle)
                    else
                      ...bookingRows.map((booking) {
                        final profile =
                            profileById[booking['user_id'].toString()];
                        final name =
                            (profile?['full_name'] ??
                                    profile?['email'] ??
                                    'Member')
                                .toString();
                        final email = (profile?['email'] ?? '').toString();
                        final status = booking['status'].toString();

                        return _AttendanceMemberCard(
                          name: name,
                          email: email,
                          status: prettyStatus(status),
                          selectedStatus: status,
                          onAttended: () => updateStatus(booking, 'attended'),
                          onNoShow: () => updateStatus(booking, 'no_show'),
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
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle section = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: 0.8,
    height: 1,
  );

  static TextStyle rowTitle = GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF8F96A3),
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
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3EA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: _AttendanceText.section.copyWith(
          color: const Color(0xFFB59B6A),
        ),
      ),
    );
  }
}

class _AttendanceMemberCard extends StatelessWidget {
  const _AttendanceMemberCard({
    required this.name,
    required this.email,
    required this.status,
    required this.selectedStatus,
    required this.onAttended,
    required this.onNoShow,
  });

  final String name;
  final String email;
  final String status;
  final String selectedStatus;
  final VoidCallback onAttended;
  final VoidCallback onNoShow;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F3EA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  name.trim().isEmpty ? 'M' : name.trim()[0].toUpperCase(),
                  style: _AttendanceText.rowTitle.copyWith(
                    color: const Color(0xFFB59B6A),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _AttendanceText.rowTitle,
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _AttendanceText.subtle,
                      ),
                    ],
                  ],
                ),
              ),
              Text(status.toUpperCase(), style: _AttendanceText.subtle),
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

class _AttendanceStatusButton extends StatelessWidget {
  const _AttendanceStatusButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final activeColor = danger
        ? const Color(0xFFB42318)
        : const Color(0xFFB59B6A);

    return SizedBox(
      height: 42,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: selected ? activeColor : Colors.white,
          foregroundColor: selected ? Colors.white : const Color(0xFF384152),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: _AttendanceText.section.copyWith(
            color: selected ? Colors.white : const Color(0xFF384152),
          ),
        ),
      ),
    );
  }
}
