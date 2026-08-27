import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/analytics_models.dart';

abstract interface class AnalyticsRepository {
  Future<AnalyticsOverview> loadOverview(AnalyticsPeriod period);
  Future<AttendanceAnalytics> loadAttendance(AnalyticsPeriod period);
  Future<MembershipAnalytics> loadMemberships(AnalyticsPeriod period);
  Future<RevenueAnalytics> loadRevenue(AnalyticsPeriod period);
  Future<RetentionSummary> loadRetentionSummary();
  Future<RetentionPage> loadRetentionSegment(
    RetentionSegment segment, {
    required int limit,
    required int offset,
  });
  Future<RetentionCommunicationResult> sendRetentionCommunication({
    required List<String> recipientIds,
    required String title,
    required String body,
  });
}

class SupabaseAnalyticsRepository implements AnalyticsRepository {
  const SupabaseAnalyticsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AnalyticsOverview> loadOverview(AnalyticsPeriod period) async {
    final response = await _client.rpc(
      'get_effective_analytics_overview',
      params: {'p_period': period.apiValue},
    );
    return AnalyticsOverview.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<AttendanceAnalytics> loadAttendance(AnalyticsPeriod period) async {
    final response = await _client.rpc(
      'get_effective_attendance_analytics',
      params: {'p_period': period.apiValue},
    );
    return AttendanceAnalytics.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<MembershipAnalytics> loadMemberships(AnalyticsPeriod period) async {
    final response = await _client.rpc(
      'get_effective_membership_analytics',
      params: {'p_period': period.apiValue},
    );
    return MembershipAnalytics.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<RevenueAnalytics> loadRevenue(AnalyticsPeriod period) async {
    final response = await _client.rpc(
      'get_effective_revenue_analytics',
      params: {'p_period': period.apiValue},
    );
    return RevenueAnalytics.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<RetentionSummary> loadRetentionSummary() async {
    final response = await _client.rpc('get_effective_retention_summary');
    return RetentionSummary.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<RetentionPage> loadRetentionSegment(
    RetentionSegment segment, {
    required int limit,
    required int offset,
  }) async {
    final response = await _client.rpc(
      'list_effective_retention_segment',
      params: {
        'p_segment': segment.apiValue,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return RetentionPage.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<RetentionCommunicationResult> sendRetentionCommunication({
    required List<String> recipientIds,
    required String title,
    required String body,
  }) async {
    final response = await _client.rpc(
      'send_effective_retention_communication',
      params: {
        'p_recipient_ids': recipientIds,
        'p_title': title,
        'p_body': body,
      },
    );
    return RetentionCommunicationResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}
