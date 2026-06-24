import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart' show v1Base;
import '_crash_reporter.dart';
import 'auth_service.dart';

/// Apple §1.2 / Google Play UGC requires user-level block + report
/// surfaces. This service is the single client-side entry point.
///
/// Backend endpoints may or may not be deployed yet — on 404 we throw
/// a typed [ModerationException] with `statusCode: 404` so the UI can
/// degrade gracefully to "feature coming soon" rather than red errors.
class ModerationService {
  ModerationService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  static const Duration _timeout = Duration(seconds: 12);

  /// Local cache of blocked user IDs. Used for defense-in-depth filtering
  /// of feed / comments / suggestions until the backend enforces.
  /// Cleared on logout via [clearLocalCache] (main.dart teardown).
  static const String _kBlockedIdsKey = 'blocked_user_ids_v1';

  /// Wipe the per-user local moderation cache. Called from the logout
  /// teardown so the previous user's block list can't leak to the next
  /// account on this device.
  static Future<void> clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBlockedIdsKey);
  }

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getAccessToken();
    if (token == null) {
      throw ModerationException('Not signed in', statusCode: 401);
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _headers();
    try {
      switch (method) {
        case 'POST':
          return await http
              .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
              .timeout(_timeout);
        case 'DELETE':
          return await http.delete(uri, headers: headers).timeout(_timeout);
        case 'GET':
        default:
          return await http.get(uri, headers: headers).timeout(_timeout);
      }
    } on SocketException catch (e) {
      throw ModerationException('Network unavailable: ${e.message}', isNetworkError: true);
    } on TimeoutException {
      throw ModerationException('Request timed out', isNetworkError: true);
    } on http.ClientException catch (e) {
      throw ModerationException('Network error: ${e.message}', isNetworkError: true);
    }
  }

  /// POST /v1/users/{userId}/block — also updates the local block cache so
  /// the UI can filter posts/comments client-side immediately.
  Future<void> blockUser(String userId) async {
    try {
      final res = await _send('POST', Uri.parse('$v1Base/users/$userId/block'));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ModerationException(
          'Could not block user (${res.statusCode})',
          statusCode: res.statusCode,
        );
      }
    } catch (e, st) {
      if (e is! ModerationException) {
        reportError(e, st, reason: 'moderation:block');
        rethrow;
      }
      if (e.statusCode != 404) {
        reportError(e, st, reason: 'moderation:block');
      }
      // 404 → still cache locally so the UX is consistent; rethrow for caller.
      await _addToLocalCache(userId);
      rethrow;
    }
    await _addToLocalCache(userId);
  }

  /// DELETE /v1/users/{userId}/block — also removes from local cache.
  Future<void> unblockUser(String userId) async {
    try {
      final res = await _send('DELETE', Uri.parse('$v1Base/users/$userId/block'));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ModerationException(
          'Could not unblock user (${res.statusCode})',
          statusCode: res.statusCode,
        );
      }
    } catch (e, st) {
      if (e is! ModerationException) {
        reportError(e, st, reason: 'moderation:unblock');
        rethrow;
      }
      if (e.statusCode != 404) {
        reportError(e, st, reason: 'moderation:unblock');
      }
      await _removeFromLocalCache(userId);
      rethrow;
    }
    await _removeFromLocalCache(userId);
  }

  /// GET /v1/me/blocked — returns the canonical server list.
  /// On 404 throws so the screen can render the "coming soon" empty state.
  Future<List<BlockedUser>> listBlocked() async {
    final res = await _send('GET', Uri.parse('$v1Base/me/blocked'));
    if (res.statusCode == 404) {
      throw ModerationException('Endpoint not deployed', statusCode: 404);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ModerationException(
        'Could not load blocked list (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(res.body);
      final raw = decoded is Map<String, dynamic>
          ? (decoded['data'] as List<dynamic>? ?? const [])
          : (decoded as List<dynamic>);
      return raw
          .whereType<Map<String, dynamic>>()
          .map(BlockedUser.fromJson)
          .toList();
    } catch (e, st) {
      reportError(e, st, reason: 'moderation:list-decode');
      throw ModerationException('Malformed blocked-list response');
    }
  }

  /// POST /v1/users/{userId}/report.
  /// Caller decides how to surface 404 — see ReportUserSheet for graceful fallback.
  Future<void> reportUser(String userId, {required String category, String? note}) async {
    final body = <String, dynamic>{'category': category};
    final trimmed = note?.trim();
    if (trimmed != null && trimmed.isNotEmpty) body['note'] = trimmed;
    final res = await _send(
      'POST',
      Uri.parse('$v1Base/users/$userId/report'),
      body: body,
    );
    if (res.statusCode == 404) {
      reportErrorNoStack(
        'Backend stub: /v1/users/$userId/report (cat=$category)',
        reason: 'moderation:report-stubbed',
      );
      throw ModerationException('Endpoint not deployed', statusCode: 404);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ModerationException(
        'Could not report user (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
  }

  // ── Local cache helpers ────────────────────────────────────────────────────

  /// Returns the locally-cached set of blocked user IDs. Used by the feed /
  /// comments layer to filter blocked content client-side as defense in depth.
  Future<Set<String>> getCachedBlockedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_kBlockedIdsKey) ?? const []).toSet();
    } catch (e) {
      debugPrint('[moderation] cache read best-effort skip: $e');
      return <String>{};
    }
  }

  Future<void> _addToLocalCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList(_kBlockedIdsKey) ?? const []).toSet()..add(userId);
      await prefs.setStringList(_kBlockedIdsKey, set.toList());
    } catch (e) {
      debugPrint('[moderation] cache add best-effort skip: $e');
    }
  }

  Future<void> _removeFromLocalCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList(_kBlockedIdsKey) ?? const []).toSet()..remove(userId);
      await prefs.setStringList(_kBlockedIdsKey, set.toList());
    } catch (e) {
      debugPrint('[moderation] cache remove best-effort skip: $e');
    }
  }

  /// Replace the local cache wholesale — used after a successful server fetch.
  Future<void> syncCacheFrom(Iterable<String> userIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kBlockedIdsKey, userIds.toSet().toList());
    } catch (e) {
      debugPrint('[moderation] cache sync best-effort skip: $e');
    }
  }
}

class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.displayName,
    this.username,
    required this.blockedAt,
  });

  final String userId;
  final String displayName;
  final String? username;
  final DateTime blockedAt;

  static BlockedUser fromJson(Map<String, dynamic> j) {
    final blocked = j['blockedAt'] as String?;
    final parsed = blocked != null ? DateTime.tryParse(blocked) : null;
    return BlockedUser(
      userId: j['userId'] as String? ?? '',
      displayName: (j['displayName'] as String?)?.trim().isNotEmpty == true
          ? (j['displayName'] as String).trim()
          : (j['username'] as String? ?? 'Blocked user'),
      username: j['username'] as String?,
      blockedAt: parsed ?? DateTime.now(),
    );
  }
}

class ModerationException implements Exception {
  ModerationException(this.message, {this.statusCode, this.isNetworkError = false});
  final String message;
  final int? statusCode;
  final bool isNetworkError;

  bool get isAuthError => statusCode == 401 || statusCode == 403;
  bool get isServerError => statusCode != null && statusCode! >= 500;
  bool get isNotDeployed => statusCode == 404;

  @override
  String toString() => 'ModerationException($message, status=$statusCode, network=$isNetworkError)';
}
