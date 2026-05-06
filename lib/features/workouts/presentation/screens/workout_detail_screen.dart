import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';

import '../widgets/workout_text_styles.dart';
import '../../../booking/presentation/widgets/booking_text_styles.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});

  final String workoutId;

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _workout;
  List<Map<String, dynamic>> _likes = [];
  List<Map<String, dynamic>> _comments = [];
  Map<String, String> _authorNames = {};

  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  bool get _liked => _likes.any((l) => l['user_id'].toString() == _userId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final workout = await _client
          .from('workouts')
          .select(
            'id, workout_date, description, image_url, programs(name), workout_likes(user_id), workout_comments(id, body, user_id, created_at)',
          )
          .eq('id', widget.workoutId)
          .single();

      final comments = List<Map<String, dynamic>>.from(
        workout['workout_comments'] ?? [],
      );

      comments.sort(
        (a, b) => (b['created_at'] ?? '').toString().compareTo(
          (a['created_at'] ?? '').toString(),
        ),
      );

      final userIds = comments
          .map((c) => c['user_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final authors = <String, String>{};

      if (userIds.isNotEmpty) {
        final profiles = await _client
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', userIds);

        for (final profile in List<Map<String, dynamic>>.from(profiles)) {
          authors[profile['id'].toString()] =
              profile['full_name']?.toString() ?? appStrings.userFallbackName;
        }
      }

      if (!mounted) return;
      setState(() {
        _workout = Map<String, dynamic>.from(workout);
        _likes = List<Map<String, dynamic>>.from(
          workout['workout_likes'] ?? [],
        );
        _comments = comments;
        _authorNames = authors;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Workout detail error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    final userId = _userId;

    if (text.isEmpty || userId == null) return;

    final res = await _client
        .from('workout_comments')
        .insert({
          'workout_id': widget.workoutId,
          'user_id': userId,
          'body': text,
        })
        .select('id, body, user_id, created_at')
        .single();

    final profile = await _client
        .from('profiles')
        .select('full_name')
        .eq('id', userId)
        .single();

    if (!mounted) return;
    setState(() {
      _comments.insert(0, Map<String, dynamic>.from(res));
      _authorNames[userId] =
          profile['full_name']?.toString() ?? appStrings.userFallbackName;
      _commentCtrl.clear();
    });
  }

  String _formatDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  String _timeAgo(String? raw) {
    if (raw == null) return '';
    final createdAt = DateTime.tryParse(raw)?.toLocal();
    if (createdAt == null) return '';

    final diff = DateTime.now().difference(createdAt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';

    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  String _displayAuthorName(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value.contains('@')) {
      return appStrings.userFallbackName;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    final program = workout?['programs'] as Map<String, dynamic>?;
    final programName =
        program?['name']?.toString() ?? appStrings.workoutFallbackTitle;
    final imageUrl = workout?['image_url']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFB59B6A)),
              )
            : workout == null
            ? Center(
                child: Text(
                  appStrings.workoutNotFound,
                  style: WorkoutTextStyles.emptyMessage,
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: Navigator.of(context).pop,
                        icon: const Icon(Icons.arrow_back),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF4EFE6),
                          foregroundColor: const Color(0xFFB59B6A),
                          fixedSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        appStrings.workoutsTitle.toUpperCase(),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0E0E11),
                          letterSpacing: -0.3,
                          height: 1.0,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 44),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          programName.toUpperCase(),
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0E0E11),
                            letterSpacing: -0.3,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatDate(workout['workout_date'].toString()),
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
                              imageUrl,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          workout['description']?.toString() ?? '',
                          style: WorkoutTextStyles.body,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _DetailStatButton(
                              icon: _liked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              label: appStrings.workoutLikesCount(
                                _likes.length,
                              ),
                              active: _liked,
                              onTap: _toggleLike,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DetailActionButton(
                                label: appStrings.workoutCommentCount(
                                  _comments.length,
                                ),
                                icon: Icons.chat_bubble_outline,
                                onTap: () => _commentFocus.requestFocus(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_comments.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        appStrings.workoutNoComments,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF8F96A3),
                          letterSpacing: 0.3,
                          height: 1.0,
                        ),
                      ),
                    )
                  else
                    ..._comments.map((comment) {
                      final userId = comment['user_id']?.toString();
                      final name = _displayAuthorName(_authorNames[userId]);

                      final initial = name.trim().isEmpty
                          ? '?'
                          : name.trim()[0].toUpperCase();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF4EFE6),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                initial,
                                style: GoogleFonts.barlowCondensed(
                                  color: const Color(0xFFB59B6A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.barlowCondensed(
                                            color: const Color(0xFF111318),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            height: 1.0,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _timeAgo(
                                          comment['created_at']?.toString(),
                                        ),
                                        style: GoogleFonts.barlowCondensed(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFF8F96A3),
                                          letterSpacing: 0.3,
                                          height: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    comment['body']?.toString() ?? '',
                                    style: GoogleFonts.barlowCondensed(
                                      color: const Color(0xFF384152),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.0,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appStrings.workoutPostScoreComments.toUpperCase(),
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111318),
                            letterSpacing: 0.8,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _commentCtrl,
                          focusNode: _commentFocus,
                          minLines: 1,
                          maxLines: 4,
                          style: GoogleFonts.barlowCondensed(
                            color: const Color(0xFF384152),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                          decoration: InputDecoration(
                            hintText: appStrings.workoutCommentHint,
                            hintStyle: GoogleFonts.barlowCondensed(
                              color: const Color(0xFF8F96A3),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.send),
                              color: const Color(0xFFB59B6A),
                              onPressed: _addComment,
                            ),
                          ),
                          onSubmitted: (_) => _addComment(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DetailStatButton extends StatelessWidget {
  const _DetailStatButton({
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
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

class _DetailActionButton extends StatelessWidget {
  const _DetailActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
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
