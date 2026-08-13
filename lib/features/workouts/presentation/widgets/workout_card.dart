import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_admin_actions.dart';
import '../screens/workout_detail_screen.dart';
import 'package:google_fonts/google_fonts.dart';

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
    this.onChanged,
    this.accentColor = AppColors.accent,
    this.useEditAction = false,
    this.showDate = true,
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
  final Future<void> Function()? onChanged;
  final Color accentColor;
  final bool useEditAction;
  final bool showDate;

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

  @override
  void didUpdateWidget(covariant WorkoutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.comments, widget.comments)) {
      _comments = widget.comments;
    }
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

  Future<void> _openSocial() async {
    await showWorkoutSocialSheet(
      context: context,
      workoutId: widget.workoutId,
      program: widget.program,
    );
    await widget.onChanged?.call();
  }

  Future<void> _showManageActions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (sheetContext) {
        return AppAdminActionSheet(
          accentColor: widget.accentColor,
          onClose: () => Navigator.pop(sheetContext),
          actions: [
            AppAdminAction(
              icon: Icons.edit_outlined,
              label: appStrings.workoutEditTitle,
              onTap: () => widget.onEdit?.call(),
            ),
            AppAdminAction(
              icon: Icons.delete_outline,
              label: appStrings.workoutDeleteAction,
              destructive: true,
              onTap: () => widget.onDelete?.call(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border(context))),
      ),
      child: Material(
        key: ValueKey('workout-${widget.workoutId}'),
        color: AppColors.background(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.showDate) ...[
                          Text(
                            widget.date.toUpperCase(),
                            style: GoogleFonts.barlow(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary(context),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 5),
                        ],
                        Text(
                          widget.program.toUpperCase(),
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(context),
                            letterSpacing: -0.3,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.canManage)
                    AppOutlinedAdminButton(
                      icon: widget.useEditAction
                          ? Icons.edit_outlined
                          : Icons.more_horiz,
                      tooltip: appStrings.workoutOptions,
                      onPressed: _showManageActions,
                      accentColor: widget.accentColor,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                widget.description,
                key: ValueKey('workout-body-${widget.workoutId}'),
                style: GoogleFonts.barlow(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary(context),
                  height: 1.35,
                ),
              ),
              if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    widget.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _InlineStat(
                    icon: _liked ? Icons.favorite : Icons.favorite_border,
                    label: '${_likes.length}',
                    active: _liked,
                    onTap: _toggleLike,
                  ),
                  const SizedBox(width: 18),
                  Tooltip(
                    message: appStrings.workoutCommentCount(_comments.length),
                    child: _InlineStat(
                      key: ValueKey(
                        'workout-comment-count-${widget.workoutId}',
                      ),
                      icon: Icons.chat_bubble_outline,
                      label: '${_comments.length}',
                      active: false,
                      onTap: _openSocial,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: ValueKey('workout-log-result-${widget.workoutId}'),
                    onPressed: _openSocial,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.accentColor,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: widget.accentColor, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      appStrings.workoutLogResult,
                      style: GoogleFonts.barlow(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
    super.key,
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
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
