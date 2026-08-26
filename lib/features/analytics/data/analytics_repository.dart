import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/analytics_models.dart';

abstract interface class AnalyticsRepository {
  Future<AnalyticsOverview> loadOverview(AnalyticsPeriod period);
  Future<AttendanceAnalytics> loadAttendance(AnalyticsPeriod period);
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
}
