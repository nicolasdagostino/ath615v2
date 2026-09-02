import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_detail_header.dart';

class ProfileAttendance {
  const ProfileAttendance({required this.startsAt, required this.className});

  final DateTime startsAt;
  final String className;
}

class AttendanceHistoryScreen extends StatelessWidget {
  const AttendanceHistoryScreen({super.key, required this.attendances});

  final List<ProfileAttendance> attendances;

  @override
  Widget build(BuildContext context) {
    final sorted = [...attendances]
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Column(
          children: [
            AppDetailHeader(
              title: appStrings.pick('ATTENDANCE', 'ASISTENCIAS'),
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: sorted.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.screenX),
                        child: Text(
                          appStrings.pick(
                            'No attendance has been recorded yet.',
                            'Todavía no hay asistencias registradas.',
                          ),
                          key: const ValueKey('attendance-history-empty'),
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySecondary(context),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('attendance-history-list'),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenX,
                        AppSpacing.md,
                        AppSpacing.screenX,
                        48,
                      ),
                      itemCount: sorted.length,
                      separatorBuilder: (_, _) => Divider(
                        height: AppSpacing.lg,
                        color: AppColors.border(context),
                      ),
                      itemBuilder: (context, index) {
                        final attendance = sorted[index];
                        final locale = appStrings.isEs ? 'es' : 'en';
                        return Semantics(
                          label: attendance.className,
                          child: Column(
                            key: ValueKey(
                              'attendance-history-${attendance.startsAt.toIso8601String()}',
                            ),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat(
                                  'd MMM y · HH:mm',
                                  locale,
                                ).format(attendance.startsAt).toUpperCase(),
                                style: AppTypography.sectionTitle(context),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                attendance.className,
                                style: AppTypography.itemTitle(context),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                appStrings.attended,
                                style: AppTypography.bodySecondary(
                                  context,
                                ).copyWith(color: AppColors.primary),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
      ),
    );
  }
}
