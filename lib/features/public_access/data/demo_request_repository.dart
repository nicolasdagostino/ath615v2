import 'package:supabase_flutter/supabase_flutter.dart';

class DemoRequestInput {
  const DemoRequestInput({
    required this.fullName,
    required this.email,
    required this.gymName,
    this.phone,
    this.approxMemberCount,
    this.message,
    required this.locale,
  });
  final String fullName;
  final String email;
  final String gymName;
  final String? phone;
  final int? approxMemberCount;
  final String? message;
  final String locale;
}

abstract interface class DemoRequestRepository {
  Future<void> submit(DemoRequestInput input);
}

class SupabaseDemoRequestRepository implements DemoRequestRepository {
  SupabaseDemoRequestRepository(this.client);
  final SupabaseClient client;

  @override
  Future<void> submit(DemoRequestInput input) async {
    await client.rpc(
      'submit_public_demo_request',
      params: {
        'p_full_name': input.fullName,
        'p_email': input.email,
        'p_phone': input.phone,
        'p_gym_name': input.gymName,
        'p_approx_member_count': input.approxMemberCount,
        'p_message': input.message,
        'p_locale': input.locale,
      },
    );
  }
}
