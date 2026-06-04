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

  Future<void> _showLikedBy() async {
    final userIds = _likes
        .map((l) => l['user_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    List<Map<String, dynamic>> profiles = [];

    if (userIds.isNotEmpty) {
      final rows = await _client
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', userIds);

      profiles = List<Map<String, dynamic>>.from(rows);
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'LIKED BY · ${profiles.length}',
                  style: WorkoutTextStyles.program,
                ),
                const SizedBox(height: 16),
                if (profiles.isEmpty)
                  Text('No likes yet.', style: WorkoutTextStyles.body)
                else
                  ...profiles.map((profile) {
                    final name =
                        profile['full_name']?.toString() ??
                        appStrings.userFallbackName;
                    final avatarUrl = profile['avatar_url']?.toString();
                    final hasAvatar =
                        avatarUrl != null && avatarUrl.trim().isNotEmpty;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundColor: const Color(0xFFF7F3EA),
                            backgroundImage: hasAvatar
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: hasAvatar
                                ? null
                                : Text(
                                    name.trim().isEmpty
                                        ? 'A'
                                        : name.trim()[0].toUpperCase(),
                                    style: GoogleFonts.barlowCondensed(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFB59B6A),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WorkoutTextStyles.stat,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    appStrings.workoutOptions.toUpperCase(),
                    style: _WorkoutOptionsText.title,
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
                    _LikeHeartButton(active: _liked, onTap: _toggleLike),
                    const SizedBox(width: 8),
                    _LikeCountButton(count: _likes.length, onTap: _showLikedBy),
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

class _LikeHeartButton extends StatelessWidget {
  const _LikeHeartButton({required this.active, required this.onTap});

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
          child: Icon(
            active ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: active ? const Color(0xFFE11D48) : const Color(0xFF667085),
          ),
        ),
      ),
    );
  }
}

class _LikeCountButton extends StatelessWidget {
  const _LikeCountButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF2F3F6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: count == 0 ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Text('$count', style: WorkoutTextStyles.stat),
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
        label: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: BookingTextStyles.button,
        ),
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

class _WorkoutOptionsText {
  const _WorkoutOptionsText._();

  static TextStyle title = GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF0E0E11),
    letterSpacing: -0.3,
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
    final color = danger ? const Color(0xFFB42318) : const Color(0xFFB59B6A);

    return Material(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: _WorkoutOptionsText.rowTitle.copyWith(
                        color: danger
                            ? const Color(0xFFB42318)
                            : const Color(0xFFB59B6A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _WorkoutOptionsText.subtle,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF8F96A3)),
            ],
          ),
        ),
      ),
    );
  }
}
