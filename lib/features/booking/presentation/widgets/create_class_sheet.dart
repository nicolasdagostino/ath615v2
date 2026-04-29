import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_button.dart';

Future<void> showCreateClassSheet({
  required BuildContext context,
  required SupabaseClient client,
  required String gymId,
  required Future<void> Function() onCreated,
}) async {
  final title = TextEditingController(text: 'CrossFit');
  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  final duration = TextEditingController(text: '60');
  final capacity = TextEditingController(text: '12');
  bool saving = false;

  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedStartsAt = selectedDate == null || selectedTime == null
              ? null
              : DateTime(
                  selectedDate!.year,
                  selectedDate!.month,
                  selectedDate!.day,
                  selectedTime!.hour,
                  selectedTime!.minute,
                );

          final isPastClass =
              selectedStartsAt != null &&
              !selectedStartsAt.isAfter(DateTime.now());

          final canCreate = selectedStartsAt != null && !isPastClass && !saving;

          Future<void> save() async {
            setSheetState(() => saving = true);

            try {
              if (selectedStartsAt == null) {
                throw Exception('Select date and time');
              }

              if (!selectedStartsAt.isAfter(DateTime.now())) {
                throw Exception('Class date and time must be in the future');
              }

              await client.from('classes').insert({
                'gym_id': gymId,
                'title': title.text.trim().isEmpty
                    ? 'Class'
                    : title.text.trim(),
                'starts_at': selectedStartsAt.toUtc().toIso8601String(),
                'duration_minutes': int.tryParse(duration.text.trim()) ?? 60,
                'capacity': int.tryParse(capacity.text.trim()) ?? 12,
                'created_by': client.auth.currentUser?.id,
              });

              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              await onCreated();
            } catch (e) {
              if (!sheetContext.mounted) return;

              await showDialog<void>(
                context: sheetContext,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: const Text('Error'),
                    content: Text(e.toString().replaceFirst('Exception: ', '')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  );
                },
              );
            } finally {
              if (sheetContext.mounted) {
                setSheetState(() => saving = false);
              }
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
                  const Text(
                    'Create class',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date'),
                    subtitle: Text(
                      selectedDate == null
                          ? 'Select date'
                          : '${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}',
                    ),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setSheetState(() => selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Time'),
                    subtitle: Text(
                      selectedTime == null
                          ? 'Select time'
                          : selectedTime!.format(context),
                    ),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setSheetState(() => selectedTime = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: duration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration minutes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Capacity'),
                  ),
                  if (isPastClass) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Choose a future date and time.',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  AppButton(
                    label: 'Create class',
                    loading: saving,
                    onPressed: canCreate ? save : null,
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
