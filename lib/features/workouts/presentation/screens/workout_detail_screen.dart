import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';

import '../widgets/workout_text_styles.dart';
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
  Map<String, String> _authorAvatars = {};
  String? _role;

  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  bool get _liked => _likes.any((l) => l['user_id'].toString() == _userId);
  bool get _canDeleteAnyComment => _role == 'admin';

  bool _canDeleteComment(Map<String, dynamic> comment) {
    final commentUserId = comment['user_id']?.toString();
    return commentUserId == _userId || _canDeleteAnyComment;
  }

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
      final user = _client.auth.currentUser;
      final currentProfile = user == null
          ? null
          : await _client
                .from('profiles')
                .select('role')
                .eq('id', user.id)
                .maybeSingle();

      final workout = await _client
          .from('workouts')
          .select(
            'id, workout_date, description, image_url, programs(name), workout_likes(user_id), workout_comments(id, body, user_id, created_at)',
          )
          .eq('id', widget.workoutId)
          .maybeSingle();

      if (workout == null) {
        if (!mounted) return;
        setState(() {
          _workout = null;
          _likes = [];
          _comments = [];
          _authorNames = {};
          _authorAvatars = {};
          _role = currentProfile?['role']?.toString();
        });
        return;
      }

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
      final avatars = <String, String>{};

      if (userIds.isNotEmpty) {
        final profiles = await _client
            .from('profiles')
            .select('id, full_name, avatar_url')
            .inFilter('id', userIds);

        for (final profile in List<Map<String, dynamic>>.from(profiles)) {
          final id = profile['id'].toString();
          authors[id] =
              profile['full_name']?.toString() ?? appStrings.userFallbackName;
          final avatarUrl = profile['avatar_url']?.toString();
          if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
            avatars[id] = avatarUrl;
          }
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
        _authorAvatars = avatars;
        _role = currentProfile?['role']?.toString();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appStrings.workoutDetailError(e))));
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

  Future<void> _deleteComment(Map<String, dynamic> comment) async {
    final commentId = comment['id']?.toString();
    if (commentId == null || !_canDeleteComment(comment)) return;

    final shouldDelete = await showModalBottomSheet<bool>(
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
                    'DELETE COMMENT',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Are you sure you want to delete this comment? This action cannot be undone.',
                    style: GoogleFonts.barlowCondensed(
                      color: const Color(0xFF384152),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF384152),
                              side: const BorderSide(color: Color(0xFF323232)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'CANCEL',
                              style: GoogleFonts.barlowCondensed(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.2,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFB42318),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'DELETE',
                              style: GoogleFonts.barlowCondensed(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.2,
                                height: 1,
                              ),
                            ),
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
      },
    );

    if (shouldDelete != true) return;

    try {
      await _client.from('workout_comments').delete().eq('id', commentId);

      if (!mounted) return;
      setState(() {
        _comments.removeWhere((c) => c['id']?.toString() == commentId);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete comment: $e')));
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
        .select('full_name, avatar_url')
        .eq('id', userId)
        .single();

    if (!mounted) return;
    setState(() {
      _comments.insert(0, Map<String, dynamic>.from(res));
      _authorNames[userId] =
          profile['full_name']?.toString() ?? appStrings.userFallbackName;
      final avatarUrl = profile['avatar_url']?.toString();
      if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
        _authorAvatars[userId] = avatarUrl;
      }
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF252525),
        body: Container(
          color: const Color(0xFF171717),
          child: SafeArea(
            bottom: false,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFB59B6A)),
                  )
                : workout == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            appStrings.workoutNotFound,
                            textAlign: TextAlign.center,
                            style: WorkoutTextStyles.emptyMessage,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 54,
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF111111),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                appStrings.cancel.toUpperCase(),
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Container(
                    color: const Color(0xFF252525),
                    child: Column(
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF171717),
                            border: Border(
                              bottom: BorderSide(
                                color: Color(0xFF2A2A2A),
                                width: 0.8,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
                          child: SizedBox(
                            height: 50,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 44,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    onPressed: Navigator.of(context).pop,
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      color: Color(0xFFB59B6A),
                                      size: 30,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      appStrings.workoutsTitle.toUpperCase(),
                                      style: GoogleFonts.barlowCondensed(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.4,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 44),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 28),
                            children: [
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    18,
                                    20,
                                    18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF171717),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFF323232),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.04,
                                        ),
                                        blurRadius: 24,
                                        offset: const Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        programName.toUpperCase(),
                                        style: GoogleFonts.barlowCondensed(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.3,
                                          height: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _formatDate(
                                          workout['workout_date'].toString(),
                                        ),
                                        style: GoogleFonts.barlowCondensed(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFFABABAB),
                                          letterSpacing: 0.3,
                                          height: 1.0,
                                        ),
                                      ),
                                      if (hasImage) ...[
                                        const SizedBox(height: 18),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Image.network(
                                            imageUrl,
                                            width: double.infinity,
                                            height: 180,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 18),
                                      Text(
                                        workout['description']?.toString() ??
                                            '',
                                        style: WorkoutTextStyles.body.copyWith(
                                          color: Colors.white,
                                          height: 1.28,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Row(
                                        children: [
                                          _DetailInlineStat(
                                            icon: _liked
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            label: '${_likes.length}',
                                            active: _liked,
                                            onTap: _toggleLike,
                                          ),
                                          const SizedBox(width: 18),
                                          _DetailInlineStat(
                                            icon: Icons.chat_bubble_outline,
                                            label: '${_comments.length}',
                                            active: false,
                                            onTap: () =>
                                                _commentFocus.requestFocus(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (_comments.isEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF252525),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.chat_bubble_outline,
                                        color: Color(0xFFB59B6A),
                                        size: 20,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        appStrings.workoutNoComments,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.barlowCondensed(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFFABABAB),
                                          letterSpacing: 0.3,
                                          height: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ..._comments.map((comment) {
                                  final userId = comment['user_id']?.toString();
                                  final name = _displayAuthorName(
                                    _authorNames[userId],
                                  );

                                  final initial = name.trim().isEmpty
                                      ? '?'
                                      : name.trim()[0].toUpperCase();
                                  final avatarUrl = _authorAvatars[userId];

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF171717),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF323232),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.03,
                                          ),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipOval(
                                          child: Container(
                                            width: 38,
                                            height: 38,
                                            alignment: Alignment.center,
                                            color: const Color(0xFF252525),
                                            child:
                                                avatarUrl == null ||
                                                    avatarUrl.trim().isEmpty
                                                ? Text(
                                                    initial,
                                                    style:
                                                        GoogleFonts.barlowCondensed(
                                                          color: const Color(
                                                            0xFFB59B6A,
                                                          ),
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          height: 1.0,
                                                        ),
                                                  )
                                                : Image.network(
                                                    avatarUrl,
                                                    width: 38,
                                                    height: 38,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style:
                                                          GoogleFonts.barlowCondensed(
                                                            color: Colors.white,
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            height: 1.0,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    _timeAgo(
                                                      comment['created_at']
                                                          ?.toString(),
                                                    ),
                                                    style:
                                                        GoogleFonts.barlowCondensed(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: const Color(
                                                            0xFFABABAB,
                                                          ),
                                                          letterSpacing: 0.3,
                                                          height: 1.0,
                                                        ),
                                                  ),
                                                  if (_canDeleteComment(
                                                    comment,
                                                  )) ...[
                                                    const SizedBox(width: 4),
                                                    IconButton(
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(
                                                            minWidth: 28,
                                                            minHeight: 28,
                                                          ),
                                                      onPressed: () =>
                                                          _deleteComment(
                                                            comment,
                                                          ),
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                        size: 18,
                                                        color: Color(
                                                          0xFFABABAB,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                comment['body']?.toString() ??
                                                    '',
                                                style:
                                                    GoogleFonts.barlowCondensed(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w500,
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
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  18,
                                  18,
                                  18,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF171717),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF323232),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      appStrings.workoutPostScoreComments
                                          .toUpperCase(),
                                      style: GoogleFonts.barlowCondensed(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
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
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        height: 1.2,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: appStrings.workoutCommentHint,
                                        hintStyle: GoogleFonts.barlowCondensed(
                                          color: const Color(0xFFABABAB),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.2,
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFF252525),
                                        contentPadding:
                                            const EdgeInsets.fromLTRB(
                                              16,
                                              15,
                                              8,
                                              15,
                                            ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF323232),
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFB59B6A),
                                            width: 1.2,
                                          ),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF323232),
                                            width: 1,
                                          ),
                                        ),
                                        suffixIcon: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: Material(
                                            color: const Color(0xFFB59B6A),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              onTap: _addComment,
                                              child: const SizedBox(
                                                width: 42,
                                                height: 42,
                                                child: Icon(
                                                  Icons.send_rounded,
                                                  color: Color(0xFF111111),
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ),
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
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _DetailInlineStat extends StatelessWidget {
  const _DetailInlineStat({
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
                color: const Color(0xFFABABAB),
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
