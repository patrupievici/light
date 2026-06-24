import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.actorId,
    required this.actorUsername,
    required this.actorDisplayName,
    required this.actorEmailHint,
    required this.payload,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String? actorId;
  final String? actorUsername;
  final String? actorDisplayName;
  final String? actorEmailHint;
  final Map<String, dynamic> payload;
  final String? readAt;
  final String createdAt;

  bool get isUnread => readAt == null;

  /// Local copy with readAt stamped — lets the list mark an item read in
  /// place instead of refetching page 1 (which reset scroll + pagination).
  AppNotification asRead() => AppNotification(
        id: id,
        type: type,
        actorId: actorId,
        actorUsername: actorUsername,
        actorDisplayName: actorDisplayName,
        actorEmailHint: actorEmailHint,
        payload: payload,
        readAt: readAt ?? DateTime.now().toUtc().toIso8601String(),
        createdAt: createdAt,
      );

  String get actorLabel {
    final d = actorDisplayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    final u = actorUsername?.trim();
    if (u != null && u.isNotEmpty) return '@$u';
    final e = actorEmailHint?.trim();
    if (e != null && e.isNotEmpty) return e;
    return 'Someone';
  }

  static AppNotification fromJson(Map<String, dynamic> j) {
    final pay = j['payload'];
    return AppNotification(
      id: j['id'] as String,
      type: j['type'] as String,
      actorId: j['actorId'] as String?,
      actorUsername: j['actorUsername'] as String?,
      actorDisplayName: j['actorDisplayName'] as String?,
      actorEmailHint: j['actorEmailHint'] as String?,
      payload: pay is Map<String, dynamic> ? pay : <String, dynamic>{},
      readAt: j['readAt'] as String?,
      createdAt: j['createdAt'] as String,
    );
  }
}

class NotificationsPage {
  const NotificationsPage({required this.items, required this.hasMore});
  final List<AppNotification> items;
  final bool hasMore;
}

class NotificationsService {
  NotificationsService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getAccessToken();
    if (token == null) throw Exception('Not signed in');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  Future<int> unreadCount() async {
    final res = await http
        .get(
          Uri.parse('$v1Base/notifications/unread-count'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return 0;
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['count'] as int? ?? 0;
  }

  Future<List<AppNotification>> list({int page = 1, int limit = 40}) async {
    final p = await listPage(page: page, limit: limit);
    return p.items;
  }

  Future<NotificationsPage> listPage({int page = 1, int limit = 40}) async {
    final res = await http
        .get(
          Uri.parse('$v1Base/notifications').replace(queryParameters: {
            'page': '$page',
            'limit': '$limit',
          }),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      // Throw so the screen's REAL error state (with retry) renders —
      // swallowing this as an empty page told users 'No notifications yet'
      // during server outages.
      throw NotificationsException(
        'Could not load notifications (HTTP ${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    final items = list
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
    return NotificationsPage(items: items, hasMore: items.length == limit);
  }

  Future<void> markRead(String id) async {
    // Timeout so a hung connection can't await forever; failures are the
    // caller's choice to surface (single-item read drift is low-stakes).
    await http
        .post(
          Uri.parse('$v1Base/notifications/$id/read'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
  }

  /// POST /v1/notifications/read-all.
  ///
  /// Wave 22 P1.6 — previously this swallowed all failures: no timeout, no
  /// status check, no return value. UI would optimistically mark items read
  /// locally even when the server 500'd, drifting the two states apart on
  /// every "Mark all read" tap during an outage.
  ///
  /// Returns `true` on 2xx. Throws [NotificationsException] on timeout /
  /// network error / non-2xx response so the caller can surface a real
  /// error state to the user.
  Future<bool> markAllRead() async {
    try {
      final res = await http
          .post(
            Uri.parse('$v1Base/notifications/read-all'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      throw NotificationsException(
        'markAllRead failed: HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    } on NotificationsException {
      rethrow;
    } catch (e) {
      throw NotificationsException('markAllRead failed: $e');
    }
  }
}

/// Typed failure from [NotificationsService] — lets the UI distinguish
/// "network down / server error" from generic exceptions and react
/// (e.g. show "couldn't mark all read" snackbar without resetting state).
class NotificationsException implements Exception {
  const NotificationsException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'NotificationsException($message)';
}
