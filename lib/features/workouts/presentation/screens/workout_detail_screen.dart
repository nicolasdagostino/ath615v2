import 'package:flutter/material.dart';

import '../../../../core/widgets/app_small_outlined_button.dart';
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
              profile['full_name']?.toString() ?? 'User';
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
      _authorNames[userId] = profile['full_name']?.toString() ?? 'User';
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

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    final program = workout?['programs'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: Text(program?['name']?.toString() ?? 'Workout')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : workout == null
          ? const Center(child: Text('Workout not found.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  program?['name']?.toString() ?? 'Workout',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_formatDate(workout['workout_date'].toString())),
                if (workout['image_url'] != null &&
                    workout['image_url'].toString().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(
                      workout['image_url'].toString(),
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(workout['description']?.toString() ?? ''),
                const SizedBox(height: 18),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _toggleLike,
                      icon: Icon(
                        _liked ? Icons.favorite : Icons.favorite_border,
                      ),
                      label: Text('${_likes.length} likes'),
                    ),
                    const SizedBox(width: 10),
                    AppSmallOutlinedButton(
                      label: '${_comments.length} comments',
                      icon: Icons.chat_bubble_outline,
                      onPressed: () => _commentFocus.requestFocus(),
                    ),
                  ],
                ),
                const Divider(height: 32),
                const Text(
                  'Post score / comments',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _commentCtrl,
                  focusNode: _commentFocus,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'How did it go?',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _addComment,
                    ),
                  ),
                  onSubmitted: (_) => _addComment(),
                ),
                const SizedBox(height: 16),
                if (_comments.isEmpty)
                  const Text('No comments yet.')
                else
                  ..._comments.map((comment) {
                    final userId = comment['user_id']?.toString();
                    final name = _authorNames[userId] ?? 'User';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE8E8E8)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                _timeAgo(comment['created_at']?.toString()),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF777777),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(comment['body']?.toString() ?? ''),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
