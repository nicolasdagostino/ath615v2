import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class OwnerRequestsDataSource {
  Future<Map<String, dynamic>> list(String filter);
  Future<Map<String, dynamic>> detail(String type, String id);
  Future<void> update(String type, String id, String status, String notes);
  Future<String?> signedAttachment(String path);
}

class OwnerRequestsRepository implements OwnerRequestsDataSource {
  OwnerRequestsRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> list(String filter) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'get_platform_owner_requests',
              params: {'p_filter': filter},
            )
            as Map,
      );
  @override
  Future<Map<String, dynamic>> detail(String type, String id) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'get_platform_owner_request',
              params: {'p_type': type, 'p_id': id},
            )
            as Map,
      );
  @override
  Future<void> update(String type, String id, String status, String notes) =>
      client.rpc(
        'update_platform_owner_request',
        params: {
          'p_type': type,
          'p_id': id,
          'p_status': status,
          'p_owner_notes': notes,
        },
      );
  @override
  Future<String?> signedAttachment(String path) async {
    final response = await client.functions.invoke(
      'submit-support-request',
      body: {'action': 'signed_url', 'path': path},
    );
    return (response.data as Map?)?['signed_url']?.toString();
  }
}
