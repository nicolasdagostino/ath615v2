import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class MemberCoachRepository {
  Future<Map<String, bool>> listCapabilities();

  Future<bool> setCapability({required String memberId, required bool isCoach});
}

class SupabaseMemberCoachRepository implements MemberCoachRepository {
  SupabaseMemberCoachRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, bool>> listCapabilities() async {
    const pageSize = 100;
    var offset = 0;
    final capabilities = <String, bool>{};

    while (true) {
      final result = await _client.rpc(
        'list_effective_gym_members',
        params: {
          'p_search': null,
          'p_role': 'all',
          'p_status': 'all',
          'p_limit': pageSize,
          'p_offset': offset,
        },
      );
      final rows = List<Map<String, dynamic>>.from(result as List);
      if (rows.isEmpty) break;

      for (final row in rows) {
        final userId = row['user_id']?.toString();
        if (userId == null || userId.isEmpty) continue;
        capabilities[userId] = row['is_coach'] == true;
      }

      final rawTotal = rows.first['total_count'];
      final total = rawTotal is num
          ? rawTotal.toInt()
          : int.tryParse(rawTotal?.toString() ?? '');
      offset += rows.length;
      if (rows.length < pageSize || (total != null && offset >= total)) break;
    }

    return capabilities;
  }

  @override
  Future<bool> setCapability({
    required String memberId,
    required bool isCoach,
  }) async {
    final result = await _client.rpc(
      'set_member_coach_capability',
      params: {'p_member_id': memberId, 'p_is_coach': isCoach},
    );
    return result == true;
  }
}
