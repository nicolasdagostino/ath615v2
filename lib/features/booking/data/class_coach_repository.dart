import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/class_coach.dart';

abstract interface class ClassCoachRepository {
  Future<List<ClassCoachOption>> listAssignable();
}

class SupabaseClassCoachRepository implements ClassCoachRepository {
  SupabaseClassCoachRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ClassCoachOption>> listAssignable() async {
    final result = await _client.rpc('list_assignable_class_coaches');
    final rows = List<Map<String, dynamic>>.from(result as List);

    return rows
        .map(ClassCoachOption.fromRpcRow)
        .whereType<ClassCoachOption>()
        .toList(growable: false);
  }
}
