import 'package:flutter/material.dart';

import '../../../../core/widgets/app_small_outlined_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    showDragHandle: true,
    isScrollControlled: true,
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

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 8,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    klass['title']?.toString() ?? 'Class',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(formatDateTime(klass['starts_at'])),
                  const SizedBox(height: 22),
                  const Text(
                    'Attendance',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  if (bookingRows.isEmpty)
                    const Text('No bookings yet.')
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

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (email.isNotEmpty) Text(email),
                              const SizedBox(height: 8),
                              Text('Status: ${prettyStatus(status)}'),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: AppSmallOutlinedButton(
                                      label: 'Attended',
                                      onPressed: () =>
                                          updateStatus(booking, 'attended'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: AppSmallOutlinedButton(
                                      label: 'No show',
                                      onPressed: () =>
                                          updateStatus(booking, 'no_show'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
