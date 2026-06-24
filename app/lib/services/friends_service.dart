import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';
import 'http_client.dart';
import 'moderation_service.dart';

String friendLabel({
  required String userId,
  required String? username,
  required String? displayName,
  required String? emailHint,
}) {
  if (displayName?.trim().isNotEmpty == true) return displayName!.trim();
  if (username != null && username.isNotEmpty) return '@$username';
  if (emailHint != null && emailHint.isNotEmpty) return emailHint;
  return userId.substring(0, 8).toUpperCase();
}

class FriendSummary {
  const FriendSummary({
    required this.userId,
    required this.username,
    required this.displayName,
    this.emailHint,
  });
  final String userId;
  final String? username;
  final String? displayName;
  final String? emailHint;

  static FriendSummary fromJson(Map<String, dynamic> j) => FriendSummary(
        userId: j['userId'] as String,
        username: j['username'] as String?,
        displayName: j['displayName'] as String?,
        emailHint: j['emailHint'] as String?,
      );

  String get label => friendLabel(
        userId: userId,
        username: username,
        displayName: displayName,
        emailHint: emailHint,
      );
}

class FriendRequestRow {
  const FriendRequestRow({
    required this.friendshipId,
    required this.userId,
    required this.username,
    required this.displayName,
    this.emailHint,
    required this.createdAt,
  });
  final String friendshipId;
  final String userId;
  final String? username;
  final String? displayName;
  final String? emailHint;
  final String createdAt;

  static FriendRequestRow fromJson(Map<String, dynamic> j) => FriendRequestRow(
        friendshipId: j['friendshipId'] as String,
        userId: j['userId'] as String,
        username: j['username'] as String?,
        displayName: j['displayName'] as String?,
        emailHint: j['emailHint'] as String?,
        createdAt: j['createdAt'] as String? ?? '',
      );

  String get label => friendLabel(
        userId: userId,
        username: username,
        displayName: displayName,
        emailHint: emailHint,
      );
}

class FriendsService {
  FriendsService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getAccessToken();
    if (token == null) throw Exception('Not signed in');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  Future<List<FriendSummary>> listFriends() async {
    // .withTimeout() on every call in this service — a stalled connection
    // used to leave FriendsScreen/CircleScreen on a spinner forever.
    final res = await http
        .get(Uri.parse('$v1Base/friends'), headers: await _headers())
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not load friends (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['data'] as List<dynamic>? ?? [];
    return list
        .map((e) => FriendSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FriendSummary>> searchByUsername(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final res = await http
        .get(
          Uri.parse('$v1Base/friends/search').replace(queryParameters: {'query': q}),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['data'] as List<dynamic>? ?? [];
    final all = list
        .map((e) => FriendSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    // Hide blocked users from search results — defense in depth.
    final blocked = await ModerationService().getCachedBlockedIds();
    if (blocked.isEmpty) return all;
    return all.where((u) => !blocked.contains(u.userId)).toList();
  }

  Future<List<FriendRequestRow>> _requests(String path) async {
    final res = await http
        .get(
          Uri.parse('$v1Base$path'),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['data'] as List<dynamic>? ?? [];
    return list
        .map((e) => FriendRequestRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FriendRequestRow>> incomingRequests() =>
      _requests('/friends/requests/incoming');

  Future<List<FriendRequestRow>> outgoingRequests() =>
      _requests('/friends/requests/outgoing');

  /// Trimite cerere. Dacă celălalt ți-a trimis deja, serverul poate răspunde 201 cu `accepted`.
  Future<Map<String, dynamic>> sendRequest(String userId) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/friends/requests'),
          headers: await _headers(),
          body: jsonEncode({'userId': userId}),
        )
        .withTimeout();
    final body = res.body.isNotEmpty ? jsonDecode(res.body) : <String, dynamic>{};
    if (res.statusCode != 201 && res.statusCode != 200) {
      final msg = (body is Map && body['message'] is String) ? body['message'] as String : 'Request failed';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(body as Map);
  }

  Future<void> acceptRequest(String fromUserId) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/friends/accept'),
          headers: await _headers(),
          body: jsonEncode({'userId': fromUserId}),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
      final msg = (body is Map && body['message'] is String) ? body['message'] as String : 'Accept failed';
      throw Exception(msg);
    }
  }

  Future<void> removeOrCancel(String userId) async {
    final res = await http
        .delete(
          Uri.parse('$v1Base/friends/$userId'),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
      final msg = (body is Map && body['message'] is String) ? body['message'] as String : 'Remove failed';
      throw Exception(msg);
    }
  }
}
