import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../booking/presentation/widgets/booking_text_styles.dart';
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
        builder: (_) => WorkoutDetailScreen(workoutId: widget.workoutId),
      ),
    );

    await widget.onChanged?.call();
  }

  Future<void> _showManageActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetAction(
                  icon: Icons.edit_outlined,
                  label: appStrings.workoutEdit,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onEdit?.call();
                  },
                ),
                _SheetAction(
                  icon: Icons.delete_outline,
                  label: appStrings.workoutDelete,
                  danger: true,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onDelete?.call();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String get _commentsLabel {
    if (_comments.isEmpty) {
      return appStrings.workoutPostScore;
    }

    return appStrings.workoutCommentCount(_comments.length);
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openDetail,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
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
                          color: const Color(0xFF0E0E11),
                          letterSpacing: -0.3,
                          height: 1.0,
                        ),
                      ),
                    ),
                    if (widget.canManage)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_horiz),
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
                    color: const Color(0xFF8F96A3),
                    letterSpacing: 0.3,
                    height: 1.0,
                  ),
                ),
                if (hasImage) ...[
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.network(
                      widget.imageUrl!,
                      width: double.infinity,
                      height: 230,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(widget.description, style: WorkoutTextStyles.body),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _StatButton(
                      icon: _liked ? Icons.favorite : Icons.favorite_border,
                      label: '${_likes.length}',
                      active: _liked,
                      onTap: _toggleLike,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _OpenCommentsButton(
                        label: _commentsLabel,
                        onTap: _openDetail,
                      ),
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

class _StatButton extends StatelessWidget {
  const _StatButton({
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
    return Material(
      color: active ? const Color(0xFFFFEEF1) : const Color(0xFFF2F3F6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: active
                    ? const Color(0xFFE11D48)
                    : const Color(0xFF667085),
              ),
              const SizedBox(width: 8),
              Text(label, style: WorkoutTextStyles.stat),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenCommentsButton extends StatelessWidget {
  const _OpenCommentsButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.chat_bubble_outline, size: 18),
        label: Text(label.toUpperCase(), style: BookingTextStyles.button),
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFFB59B6A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB42318) : const Color(0xFF111318);
    final bg = danger ? const Color(0xFFFFF1F0) : const Color(0xFFF4F5F7);

    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        label,
        style: BookingTextStyles.metaValue.copyWith(color: color),
      ),
      onTap: onTap,
    );
  }
}
