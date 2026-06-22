import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../screens/workout_detail_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'workout_text_styles.dart';

class WorkoutCard extends StatefulWidget {
  const WorkoutCard({
    super.key,
    required this.workoutId,
    required this.program,
    required this.description,
    required this.date,
    required this.likes,
    required this.comments,
    this.imageUrl,
    this.canManage = false,
    this.onEdit,
    this.onDelete,
    this.openDetailFromExplore = false,
    this.onChanged,
  });

  final String workoutId;
  final String program;
  final String description;
  final String date;
  final List<Map<String, dynamic>> likes;
  final List<Map<String, dynamic>> comments;
  final String? imageUrl;
  final bool canManage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool openDetailFromExplore;
  final Future<void> Function()? onChanged;

  @override
  State<WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends State<WorkoutCard> {
  late List<Map<String, dynamic>> _likes;
  late List<Map<String, dynamic>> _comments;

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  bool get _liked => _likes.any((l) => l['user_id'].toString() == _userId);

  @override
  void initState() {
    super.initState();
    _likes = widget.likes;
    _comments = widget.comments;
  }

  Future<void> _toggleLike() async {
    final userId = _userId;
    if (userId == null) return;

    if (_liked) {
      await _client
          .from('workout_likes')
          .delete()
          .eq('workout_id', widget.workoutId)
          .eq('user_id', userId);

      setState(() {
        _likes.removeWhere((l) => l['user_id'] == userId);
      });
    } else {
      await _client.from('workout_likes').insert({
        'workout_id': widget.workoutId,
        'user_id': userId,
      });

      setState(() {
        _likes.add({'user_id': userId});
      });
    }
  }

  Future<void> _openDetail() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutDetailScreen(
          workoutId: widget.workoutId,
          fromExplore: widget.openDetailFromExplore,
        ),
      ),
    );

    await widget.onChanged?.call();
  }

  Future<void> _showManageActions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(AppSpacing.sheetMargin),
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(AppRadii.panel),
                border: Border.all(color: AppColors.border(context), width: 1),
                boxShadow: AppShadows.card(context),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    widget.program.toUpperCase(),
                    style: _WorkoutOptionsText.title.copyWith(
                      color: AppColors.textPrimary(context),
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appStrings.workoutOptions.toUpperCase(),
                    style: _WorkoutOptionsText.subtle.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SheetAction(
                    icon: Icons.edit_outlined,
                    label: appStrings.workoutEdit,
                    subtitle: widget.program,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onEdit?.call();
                    },
                  ),
                  const SizedBox(height: 12),
                  _SheetAction(
                    icon: Icons.delete_outline,
                    label: appStrings.workoutDelete,
                    subtitle: widget.program,
                    danger: true,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onDelete?.call();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String get _previewDescription {
    final lines = widget.description
        .trim()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(4)
        .join('\n');

    return lines.isEmpty ? appStrings.workoutDescription : lines;
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.border(context), width: 1),
        boxShadow: AppShadows.card(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openDetail,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.program.toUpperCase(),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(context),
                          letterSpacing: -0.3,
                          height: 1.0,
                        ),
                      ),
                    ),
                    if (widget.canManage)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.more_horiz,
                          color: AppColors.textSecondary(context),
                        ),
                        onPressed: _showManageActions,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.date,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary(context),
                    letterSpacing: 0.3,
                    height: 1.0,
                  ),
                ),
                if (hasImage) ...[
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.imageUrl!,
                      width: double.infinity,
                      height: 172,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  _previewDescription,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: WorkoutTextStyles.body.copyWith(
                    color: AppColors.textPrimary(context),
                    height: 1.28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'TAP TO VIEW',
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                    letterSpacing: 0.8,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _InlineStat(
                      icon: _liked ? Icons.favorite : Icons.favorite_border,
                      label: '${_likes.length}',
                      active: _liked,
                      onTap: _toggleLike,
                    ),
                    const SizedBox(width: 18),
                    _InlineStat(
                      icon: Icons.chat_bubble_outline,
                      label: '${_comments.length}',
                      active: false,
                      onTap: _openDetail,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFE11D48) : const Color(0xFFABABAB);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary(context),
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutOptionsText {
  const _WorkoutOptionsText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.3,
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

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt(context),
      borderRadius: BorderRadius.circular(AppRadii.input),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: danger ? AppColors.danger : AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: _WorkoutOptionsText.rowTitle.copyWith(
                        color: danger
                            ? AppColors.danger
                            : AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _WorkoutOptionsText.subtle.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
