import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutCard extends StatefulWidget {
  const WorkoutCard({
    super.key,
    required this.workoutId,
    required this.program,
    required this.description,
    required this.date,
    required this.likes,
    required this.comments,
  });

  final String workoutId;
  final String program;
  final String description;
  final String date;
  final List<Map<String, dynamic>> likes;
  final List<Map<String, dynamic>> comments;

  @override
  State<WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends State<WorkoutCard> {
  late List<Map<String, dynamic>> _likes;
  late List<Map<String, dynamic>> _comments;

  final _commentCtrl = TextEditingController();

  SupabaseClient get _client => Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _likes = widget.likes;
    _comments = widget.comments;
  }

  bool get _liked => _likes.any((l) => l['user_id'].toString() == _userId);

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
    if (text.isEmpty) return;

    final userId = _userId;
    if (userId == null) return;

    final res = await _client
        .from('workout_comments')
        .insert({
          'workout_id': widget.workoutId,
          'user_id': userId,
          'body': text,
        })
        .select()
        .single();

    setState(() {
      _comments.insert(0, res);
      _commentCtrl.clear();
    });
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.program,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(widget.date),
            const SizedBox(height: 10),
            Text(widget.description),

            const SizedBox(height: 12),

            Row(
              children: [
                IconButton(
                  onPressed: _toggleLike,
                  icon: Icon(
                    _liked ? Icons.favorite : Icons.favorite_border,
                    color: _liked ? Colors.red : null,
                  ),
                ),
                Text('${_likes.length}'),
              ],
            ),

            const SizedBox(height: 8),

            TextField(
              controller: _commentCtrl,
              decoration: const InputDecoration(hintText: 'Add a comment...'),
              onSubmitted: (_) => _addComment(),
            ),

            const SizedBox(height: 8),

            ..._comments
                .take(3)
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(c['body'] ?? ''),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
