import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';
import 'http_client.dart';

class DmPeer {
  const DmPeer({required this.userId, this.username, this.displayName});
  final String userId;
  final String? username;
  final String? displayName;

  String get label {
    if (displayName?.trim().isNotEmpty == true) return displayName!.trim();
    if (username != null && username!.isNotEmpty) return '@$username';
    return userId.substring(0, 8).toUpperCase();
  }

  static DmPeer fromJson(Map<String, dynamic> j) => DmPeer(
        userId: j['userId'] as String,
        username: j['username'] as String?,
        displayName: j['displayName'] as String?,
      );
}

class DmConversationRow {
  const DmConversationRow({
    required this.conversationId,
    required this.peer,
    this.lastBody,
    this.lastCreatedAt,
    this.lastSenderId,
    required this.updatedAt,
  });
  final String conversationId;
  final DmPeer peer;
  final String? lastBody;
  final String? lastCreatedAt;
  final String? lastSenderId;
  final String updatedAt;

  static DmConversationRow fromJson(Map<String, dynamic> j) {
    final peer = DmPeer.fromJson(j['peer'] as Map<String, dynamic>);
    final last = j['lastMessage'] as Map<String, dynamic>?;
    return DmConversationRow(
      conversationId: j['conversationId'] as String,
      peer: peer,
      lastBody: last?['body'] as String?,
      lastCreatedAt: last?['createdAt'] as String?,
      lastSenderId: last?['senderId'] as String?,
      updatedAt: j['updatedAt'] as String,
    );
  }
}

class DmMessage {
  const DmMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });
  final String id;
  final String senderId;
  final String body;
  final String createdAt;

  static DmMessage fromJson(Map<String, dynamic> j) => DmMessage(
        id: j['id'] as String,
        senderId: j['senderId'] as String,
        body: j['body'] as String,
        createdAt: j['createdAt'] as String,
      );
}

/// One page of DM messages returned by [MessagesService.listMessagesPage].
///
/// `items` is ordered chronologically (oldest-first within the page).
/// `nextCursor` is the id to feed back as `before` to fetch the page of
/// older messages; `null` means there is no more history available.
class MessagesPage {
  const MessagesPage({required this.items, this.nextCursor});
  final List<DmMessage> items;
  final String? nextCursor;
}

/// REST `/v1/messages` — DM 1:1 între prieteni (backend Zvelt).
class MessagesService {
  MessagesService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() => authedJsonHeaders(auth: _auth);

  Future<List<DmConversationRow>> listConversations() async {
    final res = await http.get(
      Uri.parse('$v1Base/messages/conversations'),
      headers: await _headers(),
    ).withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Messages ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list.map((e) => DmConversationRow.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Deschide sau creează conversația cu [peerUserId] (trebuie să fie prieten).
  Future<({String conversationId, DmPeer peer})> openConversation(String peerUserId) async {
    final res = await http.post(
      Uri.parse('$v1Base/messages/conversations/open'),
      headers: await _headers(),
      body: jsonEncode({'peerUserId': peerUserId}),
    ).withTimeout();
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      final msg = err is Map && err['message'] is String ? err['message'] as String : res.body;
      throw Exception(msg);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      conversationId: data['conversationId'] as String,
      peer: DmPeer.fromJson(data['peer'] as Map<String, dynamic>),
    );
  }

  /// Backwards-compatible: returns the latest page of messages
  /// (or the page older than [before] if supplied). Existing call sites
  /// keep working — new callers should prefer [listMessagesPage].
  Future<List<DmMessage>> listMessages(
    String conversationId, {
    int limit = 80,
    String? before,
  }) async {
    final page = await listMessagesPage(
      conversationId,
      limit: limit,
      before: before,
    );
    return page.items;
  }

  /// Cursor-based pagination over a conversation's message history.
  ///
  /// Pass [before] = `null` for the first (most recent) page. To load older
  /// history, pass the id of the oldest message currently held in the UI;
  /// the backend will return up to [limit] messages strictly older than
  /// that cursor, again in chronological (oldest-first) order.
  ///
  /// Backend contract: `GET /v1/messages/conversations/{id}/messages?before=<id>&limit=80`.
  /// Response shape: `{ data: [...], next_cursor: "..." | null }`. When the
  /// server omits `next_cursor` we fall back to the earliest returned id so
  /// the UI still has a stable "load more" pivot, and bail out cleanly once
  /// fewer than [limit] messages come back.
  Future<MessagesPage> listMessagesPage(
    String conversationId, {
    int limit = 80,
    String? before,
  }) async {
    final qp = <String, String>{'limit': '$limit'};
    if (before != null && before.isNotEmpty) qp['before'] = before;
    final res = await http.get(
      Uri.parse('$v1Base/messages/conversations/$conversationId/messages')
          .replace(queryParameters: qp),
      headers: await _headers(),
    ).withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Messages ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    final items = list
        .map((e) => DmMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    final rawCursor = data['next_cursor'];
    String? nextCursor =
        (rawCursor is String && rawCursor.isNotEmpty) ? rawCursor : null;
    // Fall back to the earliest item id so callers always have a pivot when
    // the server didn't echo an explicit cursor.
    if (nextCursor == null && items.isNotEmpty && items.length >= limit) {
      nextCursor = items.first.id;
    }
    return MessagesPage(items: items, nextCursor: nextCursor);
  }

  Future<DmMessage> sendMessage(String conversationId, String body) async {
    final res = await http.post(
      Uri.parse('$v1Base/messages/conversations/$conversationId/messages'),
      headers: await _headers(),
      body: jsonEncode({'body': body}),
    ).withTimeout();
    if (res.statusCode != 201) {
      final err = jsonDecode(res.body);
      final msg = err is Map && err['message'] is String ? err['message'] as String : res.body;
      throw Exception(msg);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final m = data['message'] as Map<String, dynamic>;
    return DmMessage.fromJson(m);
  }
}
