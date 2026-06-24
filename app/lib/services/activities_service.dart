import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import 'app_data_cache.dart';
import 'auth_service.dart';
import 'http_client.dart';

/// GET /v1/activities/calendar?month=YYYY-MM (BeastRise todo #16).
class ActivitiesService {
  ActivitiesService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, Map<String, dynamic>>> getCalendarMonth(
    String yyyyMm, {
    int tzOffsetMinutes = 0,
    bool refresh = false,
  }) async {
    if (!refresh) {
      final cached = await AppDataCache.instance.loadCalendarMonth(yyyyMm);
      if (cached != null && cached.isNotEmpty) {
        return cached.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
      }
    }

    final token = await _auth.getAccessToken();
    if (token == null) {
      final cached = await AppDataCache.instance.loadCalendarMonth(yyyyMm);
      if (cached != null) {
        return cached.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
      }
      throw Exception('Not signed in');
    }
    try {
      final res = await http.get(
        Uri.parse('$v1Base/activities/calendar').replace(queryParameters: {
          'month': yyyyMm,
          'tzOffset': '$tzOffsetMinutes',
        }),
        headers: await authedReadHeaders(auth: _auth),
      ).withTimeout();
      if (res.statusCode != 200) {
        final cached = await AppDataCache.instance.loadCalendarMonth(yyyyMm);
        if (cached != null) {
          return cached.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
        }
        throw Exception('Calendar ${res.statusCode}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final days = data['days'] as Map<String, dynamic>? ?? {};
      final parsed = days.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
      await AppDataCache.instance.saveCalendarMonth(yyyyMm, parsed);
      return parsed;
    } catch (e) {
      final cached = await AppDataCache.instance.loadCalendarMonth(yyyyMm);
      if (cached != null) {
        return cached.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
      }
      rethrow;
    }
  }
}
