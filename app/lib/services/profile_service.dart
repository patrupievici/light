import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import 'app_data_cache.dart';
import 'auth_service.dart';
import 'http_client.dart';

/// Thrown by [ProfileService.updateProfile] so the UI can surface a real
/// backend error (status code + message + optional error code).
class ProfileUpdateException implements Exception {
  ProfileUpdateException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => message;
}

/// Thrown by [ProfileService.updateSettings] when a privacy/notification
/// preference fails to sync to the backend. The UI uses this to revert the
/// optimistic toggle and surface a real error.
class SettingsUpdateException implements Exception {
  SettingsUpdateException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ProfileService {
  ProfileService({AuthService? auth}) : _auth = auth ?? AuthService();

  final AuthService _auth;

  static const Duration _patchTimeout = Duration(seconds: 12);

  /// SHORT TTL for the /me cache. `/me` carries `streak.currentStreak`, which is
  /// freshness-sensitive, so keep this small to avoid showing a stale streak.
  static const Duration _meCacheTtl = Duration(minutes: 3);
  // Sidecar TTL marker for [AppDataCache.saveMe]/[loadMe], which store the
  // payload without a timestamp. We gate cache hits on this marker's age.
  static const String _meTtlKey = 'me_profile_ttl_v1';

  Future<Map<String, dynamic>?> getMe({bool refresh = false}) async {
    // Cache-first (same shape as [getDailyQuote]): serve the cached profile when
    // it's still fresh, so Home/profile don't re-fetch on every build/resume.
    if (!refresh) {
      final timed = await AppDataCache.instance.getTimed(_meTtlKey);
      if (timed != null && timed.age <= _meCacheTtl) {
        final cached = await AppDataCache.instance.loadMe();
        if (cached != null) return cached;
      }
    }

    final token = await _auth.getAccessToken();
    if (token == null) return null;
    final uri = Uri.parse('$v1Base/me');
    final http.Response res;
    try {
      res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).withTimeout();
    } catch (_) {
      // Network error — fall back to whatever we last cached (may be stale).
      return AppDataCache.instance.loadMe();
    }
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>?;
    if (decoded != null) {
      await AppDataCache.instance.saveMe(decoded);
      await AppDataCache.instance.putTimedJson(_meTtlKey, true);
    }
    return decoded;
  }

  /// Drops the cached `/me` so the next [getMe] re-fetches. Call after any
  /// mutation that changes `/me` data (profile / settings) so an edit shows
  /// immediately instead of waiting out the short TTL.
  Future<void> _invalidateMeCache() =>
      AppDataCache.instance.remove(_meTtlKey);

  /// Updates the user profile via `PATCH /v1/me/profile`.
  ///
  /// Only fields with non-null values are sent. Returns the updated profile
  /// map echoed by the backend (or `null` if the response body is empty).
  ///
  /// Validation ranges:
  /// - [displayName]: 1–40 chars (trimmed by caller)
  /// - [bio]: 0–280 chars
  /// - [bodyweightKg]: 30–250
  ///
  /// Throws [ProfileUpdateException] on any non-2xx response or network error.
  Future<Map<String, dynamic>?> updateProfile({
    String? displayName,
    String? username,
    String? bio,
    double? bodyweightKg,
    double? heightCm,
    String? sex,
    int? birthYear,
    String? unitSystem,
    String? privacyDefault,
  }) async {
    final token = await _auth.getAccessToken();
    if (token == null) {
      throw ProfileUpdateException('You are not signed in.');
    }
    final body = <String, dynamic>{
      if (displayName != null) 'displayName': displayName,
      if (username != null) 'username': username,
      if (bio != null) 'bio': bio,
      if (bodyweightKg != null) 'bodyweightKg': bodyweightKg,
      if (heightCm != null) 'heightCm': heightCm,
      if (sex != null) 'sex': sex,
      if (birthYear != null) 'birthYear': birthYear,
      if (unitSystem != null) 'unitSystem': unitSystem,
      if (privacyDefault != null) 'privacyDefault': privacyDefault,
    };
    if (body.isEmpty) return null;

    final uri = Uri.parse('$v1Base/me/profile');
    http.Response res;
    try {
      res = await http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .withTimeout(_patchTimeout);
    } on TimeoutException {
      throw ProfileUpdateException(
        'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      throw ProfileUpdateException('Network error: $e');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _invalidateMeCache();
      if (res.body.isEmpty) return null;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (e) {
        debugPrint('[ProfileService.updateProfile] best-effort skip: $e');
      }
      return null;
    }

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (e) {
      debugPrint('[ProfileService.updateProfile] error-body decode best-effort skip: $e');
    }
    final code = data?['error'] as String?;
    final serverMsg = data?['message'] as String?;
    final friendly = code == 'USERNAME_TAKEN'
        ? 'This username is already taken.'
        : (serverMsg ?? 'Update failed (HTTP ${res.statusCode}).');
    throw ProfileUpdateException(
      friendly,
      statusCode: res.statusCode,
      code: code,
    );
  }

  /// Sync a partial settings map to `PATCH /v1/me/settings`.
  ///
  /// Used by privacy / notification / discovery / DM / feed-visibility toggles
  /// so the server can enforce them (e.g., feed visibility affects API
  /// responses, discovery opt-in affects search). Device-local prefs (theme,
  /// units, language) should NOT call this — they stay in SharedPreferences.
  ///
  /// Throws [SettingsUpdateException] on any non-2xx response or network
  /// error so callers can revert the optimistic UI flip.
  Future<void> updateSettings(Map<String, dynamic> partial) async {
    if (partial.isEmpty) return;
    final token = await _auth.getAccessToken();
    if (token == null) {
      throw SettingsUpdateException('You are not signed in.');
    }
    final uri = Uri.parse('$v1Base/me/settings');
    http.Response res;
    try {
      res = await http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(partial),
          )
          .withTimeout(_patchTimeout);
    } on TimeoutException {
      throw SettingsUpdateException(
        'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      throw SettingsUpdateException('Network error: $e');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _invalidateMeCache();
      return;
    }
    String? serverMsg;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        serverMsg = decoded['message'] as String?;
      }
    } catch (e) {
      debugPrint('[ProfileService.updateSettings] error-body decode best-effort skip: $e');
    }
    throw SettingsUpdateException(
      serverMsg ?? 'Update failed (HTTP ${res.statusCode}).',
      statusCode: res.statusCode,
    );
  }

  /// GET /v1/me/daily-quote — server uses UK calendar day (pre-built @ 00:00 Europe/London).
  Future<Map<String, dynamic>> getDailyQuote({bool refresh = false}) async {
    // The quote is per calendar day — cache it under today's key so it's
    // fetched once a day, not on every Home build / app resume.
    if (!refresh) {
      final cached = await AppDataCache.instance.loadDailyQuote();
      if (cached != null) return cached;
    }

    final token = await _auth.getAccessToken();
    final uri = Uri.parse('$v1Base/me/daily-quote');

    final headers = <String, String>{
      'Cache-Control': 'no-cache',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final res = await http.get(
      uri,
      headers: headers,
    ).withTimeout();

    if (res.statusCode != 200) {
      // Fallback dacă API-ul nu merge
      return {
        'quote': 'Track it, adjust it, own the process.',
        'author': 'Zvelt Coach',
        'fallback': true,
      };
    }
    
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final q = (decoded['quote'] ?? '').toString().trim();
    if (q.isEmpty) {
      return {
        'quote': 'Track it, adjust it, own the process.',
        'author': 'Zvelt Coach',
        'fallback': true,
      };
    }
    await AppDataCache.instance.saveDailyQuote(decoded);
    return decoded;
  }
}
