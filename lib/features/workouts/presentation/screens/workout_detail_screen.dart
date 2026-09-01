import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_admin_actions.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_secondary_action_header.dart';
import '../workout_colors.dart';

import '../widgets/workout_text_styles.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> showWorkoutSocialSheet({
  required BuildContext context,
  required String workoutId,
  required String program,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    builder: (_) => FractionallySizedBox(
      key: const ValueKey('workout-social-sheet'),
      heightFactor: 0.92,
      child: WorkoutDetailScreen(
        workoutId: workoutId,
        socialOnly: true,
        programHint: program,
      ),
    ),
  );
}

class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({
    super.key,
    required this.workoutId,
    this.fromExplore = false,
    this.canManage = false,
    this.onEdit,
    this.onDelete,
    this.socialOnly = false,
    this.programHint,
  });

  final String workoutId;
  final bool fromExplore;
  final bool canManage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool socialOnly;
  final String? programHint;

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
  String? _currentAvatarUrl;
  bool _isPostingComment = false;

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
                .select('role, avatar_url')
                .eq('id', user.id)
                .maybeSingle();

      final workout = await _client
          .from('workouts')
          .select(
            'id, workout_date, description, image_url, programs(name), workout_likes(user_id)',
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
          _currentAvatarUrl = currentProfile?['avatar_url']?.toString();
        });
        return;
      }

      final commentData = await _client.rpc(
        'list_effective_workout_comments',
        params: {'p_workout_id': widget.workoutId},
      );
      final comments = List<Map<String, dynamic>>.from(
        commentData is List ? commentData : const [],
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
        _currentAvatarUrl = currentProfile?['avatar_url']?.toString();
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

    final shouldDelete = await showAppConfirmationDialog(
      context: context,
      title: appStrings.pick('Delete comment', 'Eliminar comentario'),
      message: appStrings.pick(
        'Are you sure you want to delete this comment? This action cannot be undone.',
        '¿Quieres eliminar este comentario? Esta acción no se puede deshacer.',
      ),
      confirmLabel: appStrings.pick('Delete', 'Eliminar'),
      cancelLabel: appStrings.cancel,
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

  Future<WorkoutCommentLikeResult> _toggleCommentLike(
    Map<String, dynamic> comment,
  ) async {
    final commentId = comment['id']?.toString();
    if (commentId == null) throw const FormatException('invalid_comment');
    final response = await _client.rpc(
      'toggle_workout_comment_like',
      params: {'p_comment_id': commentId},
    );
    final rows = response is List ? response : const [];
    if (rows.isEmpty) throw const FormatException('invalid_like_response');
    final row = Map<String, dynamic>.from(rows.first as Map);
    return WorkoutCommentLikeResult(
      liked: row['liked'] == true,
      count: (row['like_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    final userId = _userId;

    if (text.isEmpty || userId == null || _isPostingComment) return;

    setState(() => _isPostingComment = true);

    try {
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
        _comments.insert(0, {
          ...Map<String, dynamic>.from(res),
          'like_count': 0,
          'liked_by_me': false,
        });
        _authorNames[userId] =
            profile['full_name']?.toString() ?? appStrings.userFallbackName;
        final avatarUrl = profile['avatar_url']?.toString();
        if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
          _authorAvatars[userId] = avatarUrl;
        }
        _commentCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not post comment: $e')));
    } finally {
      if (mounted) {
        setState(() => _isPostingComment = false);
      }
    }
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

  Future<void> _showWorkoutActions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (sheetContext) => AppAdminActionSheet(
        accentColor: WorkoutColors.primary,
        onClose: () => Navigator.pop(sheetContext),
        actions: [
          AppAdminAction(
            icon: Icons.edit_outlined,
            label: appStrings.workoutEditTitle,
            onTap: () {
              Navigator.of(context).pop();
              widget.onEdit?.call();
            },
          ),
          AppAdminAction(
            icon: Icons.delete_outline,
            label: appStrings.workoutDeleteAction,
            destructive: true,
            onTap: () {
              Navigator.of(context).pop();
              widget.onDelete?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _socialAvatar(String? avatarUrl, String name) {
    return AppAvatar(
      name: name,
      avatarUrl: avatarUrl,
      size: 38,
      maxInitials: 1,
      foregroundColor: WorkoutColors.primary,
      textStyle: GoogleFonts.barlow(
        color: WorkoutColors.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildSocialOnly(String programName) {
    return Material(
      color: AppColors.surface(context),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenX,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Text(
                        appStrings.workoutCommentsTitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary(context),
                            ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('workout-social-close'),
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      onPressed: Navigator.of(context).pop,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: WorkoutColors.primary,
                    ),
                  )
                : ListView(
                    key: const ValueKey('workout-social-comments'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenX,
                      AppSpacing.md,
                      AppSpacing.screenX,
                      AppSpacing.xl,
                    ),
                    children: [
                      Text(
                        appStrings
                            .workoutLikesCount(_likes.length)
                            .toUpperCase(),
                        style: AppTypography.sectionTitle(context),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        appStrings.workoutCommentsTitle,
                        style: AppTypography.sectionTitle(context),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_comments.isEmpty)
                        Text(
                          appStrings.workoutNoComments,
                          style: AppTypography.bodySecondary(context),
                        )
                      else
                        for (final comment in _comments) ...[
                          Builder(
                            builder: (context) {
                              final userId = comment['user_id']?.toString();
                              final name = _displayAuthorName(
                                _authorNames[userId],
                              );
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _socialAvatar(_authorAvatars[userId], name),
                                    const SizedBox(width: AppSpacing.sm),
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
                                                  style:
                                                      AppTypography.itemTitle(
                                                        context,
                                                      ),
                                                ),
                                              ),
                                              Text(
                                                _timeAgo(
                                                  comment['created_at']
                                                      ?.toString(),
                                                ),
                                                style: AppTypography.helper(
                                                  context,
                                                ),
                                              ),
                                              if (_canDeleteComment(comment))
                                                IconButton(
                                                  constraints:
                                                      const BoxConstraints.tightFor(
                                                        width: 36,
                                                        height: 36,
                                                      ),
                                                  onPressed: () =>
                                                      _deleteComment(comment),
                                                  icon: Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                    color:
                                                        AppColors.textSecondary(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          Text(
                                            comment['body']?.toString() ?? '',
                                            style: AppTypography.body(context),
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          WorkoutCommentLikeButton(
                                            liked:
                                                comment['liked_by_me'] == true,
                                            count:
                                                (comment['like_count'] as num?)
                                                    ?.toInt() ??
                                                0,
                                            onToggle: () =>
                                                _toggleCommentLike(comment),
                                            onError: () =>
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      appStrings
                                                          .workoutCommentLikeError,
                                                    ),
                                                  ),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          Divider(color: AppColors.border(context), height: 1),
                        ],
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                AppSpacing.sm,
                AppSpacing.screenX,
                AppSpacing.sm + MediaQuery.viewInsetsOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                border: Border(
                  top: BorderSide(color: AppColors.border(context)),
                ),
              ),
              child: Row(
                children: [
                  _socialAvatar(_currentAvatarUrl, ''),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('workout-social-composer'),
                      controller: _commentCtrl,
                      focusNode: _commentFocus,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: appStrings.workoutCommentHint,
                        filled: true,
                        fillColor: AppColors.surfaceAlt(context),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.input),
                          borderSide: BorderSide(
                            color: AppColors.border(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.input),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.2,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.input),
                          borderSide: BorderSide(
                            color: AppColors.border(context),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _addComment(),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('workout-social-send'),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    onPressed: _isPostingComment ? null : _addComment,
                    icon: _isPostingComment
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WorkoutColors.primary,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: WorkoutColors.primary,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    final program = workout?['programs'] as Map<String, dynamic>?;
    final programName =
        program?['name']?.toString() ?? appStrings.workoutFallbackTitle;
    final imageUrl = workout?['image_url']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    if (widget.socialOnly) {
      return _buildSocialOnly(widget.programHint ?? programName);
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        body: Container(
          color: AppColors.background(context),
          child: SafeArea(
            bottom: false,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: WorkoutColors.primary,
                    ),
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
                                backgroundColor: AppColors.surfaceAlt(context),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.card,
                                  ),
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
                    color: AppColors.background(context),
                    child: Column(
                      children: [
                        AppSecondaryActionHeader(
                          key: const ValueKey('workout-detail-header'),
                          onBack: Navigator.of(context).pop,
                          action: widget.canManage
                              ? AppOutlinedAdminButton(
                                  key: const ValueKey(
                                    'workout-detail-admin-edit',
                                  ),
                                  icon: Icons.edit_outlined,
                                  tooltip: appStrings.workoutOptions,
                                  onPressed: _showWorkoutActions,
                                  accentColor: WorkoutColors.primary,
                                )
                              : null,
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 16, 0, 28),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.screenX,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: AppColors.border(context),
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        programName.toUpperCase(),
                                        style: GoogleFonts.barlowCondensed(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary(context),
                                          letterSpacing: -0.3,
                                          height: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
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
                                        style: GoogleFonts.barlow(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary(context),
                                          height: 1.38,
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
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 16,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.chat_bubble_outline,
                                        color: WorkoutColors.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        appStrings.workoutNoComments,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.barlow(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textSecondary(
                                            context,
                                          ),
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
                                    margin: const EdgeInsets.fromLTRB(
                                      22,
                                      0,
                                      22,
                                      0,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      12,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: AppColors.border(context),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AppAvatar(
                                          name: name.isEmpty ? initial : name,
                                          avatarUrl: avatarUrl,
                                          size: 38,
                                          maxInitials: 1,
                                          backgroundColor: AppColors.surface(
                                            context,
                                          ),
                                          textStyle:
                                              GoogleFonts.barlowCondensed(
                                                color: WorkoutColors.primary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                height: 1,
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
                                                      style: GoogleFonts.barlow(
                                                        color:
                                                            AppColors.textPrimary(
                                                              context,
                                                            ),
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
                                                    style: GoogleFonts.barlow(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color:
                                                          AppColors.textSecondary(
                                                            context,
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
                                                      icon: Icon(
                                                        Icons.delete_outline,
                                                        size: 18,
                                                        color:
                                                            AppColors.textSecondary(
                                                              context,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                comment['body']?.toString() ??
                                                    '',
                                                style: GoogleFonts.barlow(
                                                  color: AppColors.textPrimary(
                                                    context,
                                                  ),
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  letterSpacing: 0.0,
                                                  height: 1.3,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              WorkoutCommentLikeButton(
                                                liked:
                                                    comment['liked_by_me'] ==
                                                    true,
                                                count:
                                                    (comment['like_count']
                                                            as num?)
                                                        ?.toInt() ??
                                                    0,
                                                onToggle: () =>
                                                    _toggleCommentLike(comment),
                                                onError: () =>
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          appStrings
                                                              .workoutCommentLikeError,
                                                        ),
                                                      ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              const SizedBox(height: 4),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  16,
                                  16,
                                  16,
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
                                        color: AppColors.textPrimary(context),
                                        letterSpacing: 0.8,
                                        height: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: AppColors.surfaceAlt(
                                            context,
                                          ),
                                          foregroundImage:
                                              _currentAvatarUrl != null &&
                                                  _currentAvatarUrl!.isNotEmpty
                                              ? NetworkImage(_currentAvatarUrl!)
                                              : null,
                                          child:
                                              _currentAvatarUrl == null ||
                                                  _currentAvatarUrl!.isEmpty
                                              ? Icon(
                                                  Icons.person_outline_rounded,
                                                  color: AppColors.primary,
                                                  size: 18,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          child: TextField(
                                            controller: _commentCtrl,
                                            focusNode: _commentFocus,
                                            minLines: 1,
                                            maxLines: 4,
                                            style: GoogleFonts.barlow(
                                              color: AppColors.textPrimary(
                                                context,
                                              ),
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              height: 1.2,
                                            ),
                                            decoration: InputDecoration(
                                              hintText:
                                                  appStrings.workoutCommentHint,
                                              hintStyle: GoogleFonts.barlow(
                                                color: AppColors.textSecondary(
                                                  context,
                                                ),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: 0.2,
                                              ),
                                              filled: true,
                                              fillColor: AppColors.surfaceAlt(
                                                context,
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.fromLTRB(
                                                    14,
                                                    12,
                                                    14,
                                                    12,
                                                  ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                borderSide: BorderSide(
                                                  color: AppColors.border(
                                                    context,
                                                  ),
                                                  width: 1,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                borderSide: const BorderSide(
                                                  color: WorkoutColors.primary,
                                                  width: 1.2,
                                                ),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                borderSide: BorderSide(
                                                  color: AppColors.border(
                                                    context,
                                                  ),
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                            onSubmitted: (_) {
                                              if (!_isPostingComment) {
                                                _addComment();
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Material(
                                          color: WorkoutColors.primary,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            onTap: _isPostingComment
                                                ? null
                                                : _addComment,
                                            child: SizedBox(
                                              width: 44,
                                              height: 44,
                                              child: _isPostingComment
                                                  ? SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    )
                                                  : Icon(
                                                      Icons.send_rounded,
                                                      color: Colors.white,
                                                      size: 17,
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ],
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

class WorkoutCommentLikeResult {
  const WorkoutCommentLikeResult({required this.liked, required this.count});

  final bool liked;
  final int count;
}

class WorkoutCommentLikeButton extends StatefulWidget {
  const WorkoutCommentLikeButton({
    super.key,
    required this.liked,
    required this.count,
    required this.onToggle,
    required this.onError,
  });

  final bool liked;
  final int count;
  final Future<WorkoutCommentLikeResult> Function() onToggle;
  final VoidCallback onError;

  @override
  State<WorkoutCommentLikeButton> createState() =>
      _WorkoutCommentLikeButtonState();
}

class _WorkoutCommentLikeButtonState extends State<WorkoutCommentLikeButton> {
  late bool _liked = widget.liked;
  late int _count = widget.count;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant WorkoutCommentLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy &&
        (oldWidget.liked != widget.liked || oldWidget.count != widget.count)) {
      _liked = widget.liked;
      _count = widget.count;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final oldLiked = _liked;
    final oldCount = _count;
    setState(() {
      _busy = true;
      _liked = !oldLiked;
      _count = (oldCount + (oldLiked ? -1 : 1)).clamp(0, 1 << 31);
    });
    try {
      final result = await widget.onToggle();
      if (!mounted) return;
      setState(() {
        _liked = result.liked;
        _count = result.count;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = oldLiked;
        _count = oldCount;
        _busy = false;
      });
      widget.onError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _liked
        ? WorkoutColors.primary
        : AppColors.textSecondary(context);
    return Semantics(
      button: true,
      toggled: _liked,
      label: _liked
          ? appStrings.pick('Unlike comment', 'Quitar me gusta del comentario')
          : appStrings.pick('Like comment', 'Me gusta el comentario'),
      child: InkWell(
        key: const ValueKey('workout-comment-like'),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: _busy ? null : _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _liked ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(_liked ? 'comment-liked' : 'comment-unliked'),
                size: 17,
                color: color,
              ),
              if (_count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '$_count',
                  key: const ValueKey('workout-comment-like-count'),
                  style: AppTypography.helper(
                    context,
                  ).copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
