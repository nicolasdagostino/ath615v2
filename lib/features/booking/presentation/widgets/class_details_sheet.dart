import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';

Future<void> showClassDetailsSheet({
  required BuildContext context,
  required SupabaseClient client,
  required Map<String, dynamic> klass,
}) async {
  final classId = klass['id'].toString();

  final bookings = await client
      .from('class_bookings')
      .select('user_id, guest_name, is_guest, created_at')
      .eq('class_id', classId)
      .neq('status', 'cancelled')
      .order('created_at', ascending: true);

  final waitlist = await client
      .from('class_waitlist')
      .select('user_id, created_at')
      .eq('class_id', classId)
      .order('created_at', ascending: true);

  final bookingRows = List<Map<String, dynamic>>.from(bookings);
  final waitlistRows = List<Map<String, dynamic>>.from(waitlist);
  final currentUserId = client.auth.currentUser?.id;
  final myWaitlistIndex = currentUserId == null
      ? -1
      : waitlistRows.indexWhere(
          (row) => row['user_id']?.toString() == currentUserId,
        );
  final myWaitlistPosition = myWaitlistIndex >= 0 ? myWaitlistIndex + 1 : null;

  final userIds = <String>{
    ...bookingRows
        .where((b) => b['user_id'] != null)
        .map((b) => b['user_id'].toString()),
    ...waitlistRows.map((w) => w['user_id'].toString()),
  }.toList();

  final profiles = userIds.isEmpty
      ? <Map<String, dynamic>>[]
      : List<Map<String, dynamic>>.from(
          await client
              .from('profiles')
              .select('id, full_name, avatar_url')
              .inFilter('id', userIds),
        );

  final profileById = {for (final p in profiles) p['id'].toString(): p};

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final startsAt = DateTime.parse(klass['starts_at']).toLocal();
      final timeLabel =
          '${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}';
      final title =
          klass['title']?.toString().toUpperCase() ??
          appStrings.classFallback.toUpperCase();
      final capacity = klass['capacity'] as int? ?? 0;

      return SafeArea(
        child: Container(
          margin: EdgeInsets.all(AppSpacing.sheetMargin),
          padding: EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.surface(sheetContext),
            borderRadius: BorderRadius.circular(AppRadii.sheet),
            border: Border.all(color: AppColors.border(sheetContext), width: 1),
            boxShadow: AppShadows.card(sheetContext),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Row(
                children: [
                  Text(
                    timeLabel,
                    style: _ClassDetailsText.time.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _ClassDetailsText.title.copyWith(
                        color: AppColors.textPrimary(sheetContext),
                      ),
                    ),
                  ),
                ],
              ),
              if (myWaitlistPosition != null) ...[
                const SizedBox(height: 16),
                _ClassDetailsPositionPill(position: myWaitlistPosition),
              ],
              const SizedBox(height: 18),
              _ClassDetailsSectionHeader(
                title: appStrings.attending,
                count: '${bookingRows.length} / $capacity',
              ),
              const SizedBox(height: 8),
              if (bookingRows.isEmpty)
                _ClassDetailsEmptyText(label: appStrings.noBookingsYet)
              else
                ...bookingRows.map((booking) {
                  final isGuest = booking['is_guest'] == true;
                  final userId = booking['user_id']?.toString();
                  final profile = userId == null ? null : profileById[userId];
                  final name = isGuest
                      ? booking['guest_name']?.toString()
                      : profile?['full_name']?.toString();
                  final avatarUrl = isGuest
                      ? null
                      : profile?['avatar_url']?.toString();

                  return _ClassDetailsMemberRow(
                    name: (name == null || name.trim().isEmpty)
                        ? appStrings.member
                        : name.trim(),
                    avatarUrl: avatarUrl,
                  );
                }),
              const SizedBox(height: 18),
              _ClassDetailsSectionHeader(
                title: appStrings.waitlist,
                count: waitlistRows.length.toString(),
              ),
              const SizedBox(height: 8),
              if (waitlistRows.isEmpty)
                _ClassDetailsEmptyText(label: appStrings.noWaitlistYet)
              else
                ...waitlistRows.asMap().entries.map((entry) {
                  final index = entry.key;
                  final wait = entry.value;
                  final profile = profileById[wait['user_id'].toString()];
                  final name = profile?['full_name']?.toString();
                  final avatarUrl = profile?['avatar_url']?.toString();

                  return _ClassDetailsMemberRow(
                    name: (name == null || name.trim().isEmpty)
                        ? appStrings.member
                        : name.trim(),
                    avatarUrl: avatarUrl,
                    position: index + 1,
                  );
                }),
            ],
          ),
        ),
      );
    },
  );
}

class _ClassDetailsText {
  const _ClassDetailsText._();

  static TextStyle time = GoogleFonts.barlowCondensed(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    height: 1,
  );

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    height: 1,
  );

  static TextStyle section = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    height: 1,
  );

  static TextStyle rowTitle = GoogleFonts.barlowCondensed(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    height: 1,
  );

  static TextStyle subtle = GoogleFonts.barlowCondensed(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1,
  );
}

class _ClassDetailsPositionPill extends StatelessWidget {
  const _ClassDetailsPositionPill({required this.position});

  final int position;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            color: AppColors.accent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            appStrings.bookingWaitlistPosition(position).toUpperCase(),
            style: _ClassDetailsText.section.copyWith(color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _ClassDetailsSectionHeader extends StatelessWidget {
  const _ClassDetailsSectionHeader({required this.title, required this.count});

  final String title;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: _ClassDetailsText.section.copyWith(
            color: AppColors.textPrimary(context),
          ),
        ),
        const Spacer(),
        Container(
          height: 30,
          constraints: const BoxConstraints(minWidth: 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border(context), width: 1),
          ),
          child: Text(
            count,
            style: _ClassDetailsText.section.copyWith(color: AppColors.accent),
          ),
        ),
      ],
    );
  }
}

class _ClassDetailsMemberRow extends StatelessWidget {
  const _ClassDetailsMemberRow({
    required this.name,
    required this.avatarUrl,
    this.position,
  });

  final String name;
  final String? avatarUrl;
  final int? position;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border(context), width: 1),
      ),
      child: Row(
        children: [
          if (position != null) ...[
            SizedBox(
              width: 24,
              child: Text(
                '#$position',
                style: _ClassDetailsText.section.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          _ClassDetailsAvatar(name: name, avatarUrl: avatarUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _ClassDetailsText.rowTitle.copyWith(
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassDetailsAvatar extends StatelessWidget {
  const _ClassDetailsAvatar({required this.name, required this.avatarUrl});

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
                style: _ClassDetailsText.rowTitle.copyWith(
                  color: AppColors.accent,
                ),
              ),
      ),
    );
  }
}

class _ClassDetailsEmptyText extends StatelessWidget {
  const _ClassDetailsEmptyText({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: _ClassDetailsText.subtle.copyWith(
        color: AppColors.textSecondary(context),
      ),
    );
  }
}
