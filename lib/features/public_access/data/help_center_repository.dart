import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupportRequestInput {
  const SupportRequestInput({
    required this.fullName,
    required this.email,
    this.gymName,
    required this.issueType,
    this.screenName,
    required this.description,
    required this.locale,
    this.attachmentBytes,
    this.attachmentMime,
  });
  final String fullName, email, issueType, description, locale;
  final String? gymName, screenName, attachmentMime;
  final List<int>? attachmentBytes;
}

class ContactRequestInput {
  const ContactRequestInput({
    required this.fullName,
    required this.email,
    this.gymName,
    required this.subject,
    required this.message,
    required this.locale,
  });
  final String fullName, email, subject, message, locale;
  final String? gymName;
}

abstract interface class HelpCenterRepository {
  Future<void> submitSupport(SupportRequestInput input);
  Future<void> submitContact(ContactRequestInput input);
  Future<List<Map<String, dynamic>>> getPlans();
  Future<Map<String, dynamic>?> getAdminPlan();
  Future<Map<String, dynamic>?> getPendingPlanRequest();
  Future<void> requestPlan(String code);
  Future<void> cancelPlanRequest(String id);
}

class SupabaseHelpCenterRepository implements HelpCenterRepository {
  SupabaseHelpCenterRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> submitSupport(SupportRequestInput i) async {
    final info = await PackageInfo.fromPlatform();
    await client.functions.invoke(
      'submit-support-request',
      body: {
        'full_name': i.fullName,
        'email': i.email,
        'gym_name': i.gymName,
        'issue_type': i.issueType,
        'screen_name': i.screenName,
        'description': i.description,
        'app_version': info.version,
        'build_number': info.buildNumber,
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'locale': i.locale,
        if (i.attachmentBytes != null)
          'attachment_base64': base64Encode(i.attachmentBytes!),
        if (i.attachmentMime != null) 'attachment_mime': i.attachmentMime,
      },
    );
  }

  @override
  Future<void> submitContact(ContactRequestInput i) => client.rpc(
    'submit_public_contact_request',
    params: {
      'p_full_name': i.fullName,
      'p_email': i.email,
      'p_gym_name': i.gymName,
      'p_subject': i.subject,
      'p_message': i.message,
      'p_locale': i.locale,
    },
  );
  @override
  Future<List<Map<String, dynamic>>> getPlans() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('get_public_saas_plan_catalog') as List,
      );
  @override
  Future<Map<String, dynamic>?> getAdminPlan() async {
    if (client.auth.currentUser == null) return null;
    try {
      final rows = List<Map<String, dynamic>>.from(
        await client.rpc('get_effective_gym_saas_usage') as List,
      );
      return rows.firstOrNull;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getPendingPlanRequest() async {
    if (client.auth.currentUser == null) return null;
    try {
      final rows = List<Map<String, dynamic>>.from(
        await client.rpc('get_effective_gym_pending_saas_plan_change') as List,
      );
      return rows.firstOrNull;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> requestPlan(String code) => client.rpc(
    'request_effective_gym_saas_plan_change',
    params: {'p_requested_plan_code': code},
  );
  @override
  Future<void> cancelPlanRequest(String id) => client.rpc(
    'cancel_effective_gym_saas_plan_change',
    params: {'p_request_id': id},
  );
}
