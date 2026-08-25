import 'package:supabase_flutter/supabase_flutter.dart';

class MemberStaffNote {
  const MemberStaffNote({
    required this.id,
    required this.memberUserId,
    required this.body,
    required this.isPinned,
    required this.authorName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MemberStaffNote.fromJson(Map<String, dynamic> json) =>
      MemberStaffNote(
        id: json['note_id'].toString(),
        memberUserId: json['member_user_id'].toString(),
        body: json['body'].toString(),
        isPinned: json['is_pinned'] == true,
        authorName: json['author_name']?.toString() ?? 'Staff',
        createdAt: DateTime.parse(json['created_at'].toString()).toLocal(),
        updatedAt: DateTime.parse(json['updated_at'].toString()).toLocal(),
      );

  final String id;
  final String memberUserId;
  final String body;
  final bool isPinned;
  final String authorName;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class MemberStaffNotesRepository {
  Future<List<MemberStaffNote>> listForMember(String memberUserId);
  Future<Map<String, String>> listPinnedForMembers(List<String> memberUserIds);
  Future<void> save({
    required String memberUserId,
    required String body,
    required bool isPinned,
    String? noteId,
  });
  Future<void> delete(String noteId);
}

Future<Map<String, String>> loadBriefingPinnedNotes(
  MemberStaffNotesRepository repository,
  Iterable<String> memberUserIds,
) {
  final uniqueIds = memberUserIds.where((id) => id.isNotEmpty).toSet().toList();
  return repository.listPinnedForMembers(uniqueIds);
}

class SupabaseMemberStaffNotesRepository implements MemberStaffNotesRepository {
  const SupabaseMemberStaffNotesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<MemberStaffNote>> listForMember(String memberUserId) async {
    final result = await _client.rpc(
      'list_effective_member_staff_notes',
      params: {'p_member_user_id': memberUserId},
    );
    return List<Map<String, dynamic>>.from(
      result as List,
    ).map(MemberStaffNote.fromJson).toList();
  }

  @override
  Future<Map<String, String>> listPinnedForMembers(
    List<String> memberUserIds,
  ) async {
    if (memberUserIds.isEmpty) return const {};
    final result = await _client.rpc(
      'list_effective_member_pinned_notes',
      params: {'p_member_user_ids': memberUserIds},
    );
    return {
      for (final row in List<Map<String, dynamic>>.from(result as List))
        row['member_user_id'].toString(): row['body'].toString(),
    };
  }

  @override
  Future<void> save({
    required String memberUserId,
    required String body,
    required bool isPinned,
    String? noteId,
  }) async {
    await _client.rpc(
      'save_member_staff_note',
      params: {
        'p_member_user_id': memberUserId,
        'p_body': body.trim(),
        'p_is_pinned': isPinned,
        'p_note_id': noteId,
      },
    );
  }

  @override
  Future<void> delete(String noteId) =>
      _client.rpc('delete_member_staff_note', params: {'p_note_id': noteId});
}
