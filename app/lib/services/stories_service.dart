import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';

/// Top-level so `compute()` can run it in an isolate — base64-encoding a
/// 100KB–1.8MB image off the UI thread (same pattern as the post composer).
String _encodeBytesToBase64(Uint8List bytes) => base64Encode(bytes);

/// Below this, inline encoding is cheaper than the isolate spawn.
const int _kIsolateEncodeThresholdBytes = 100 * 1024;

/// One ephemeral (24h) story. Mirrors `GET /v1/stories/feed` items.
class Story {
  const Story({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.caption,
    required this.imageUrl,
    required this.location,
    required this.expiresAt,
    required this.createdAt,
    required this.likeCount,
    required this.likedByMe,
  });

  final String id;
  final String userId;
  final String authorName;
  final String? caption;
  final String? imageUrl;
  final String? location;
  final DateTime expiresAt;
  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;

  factory Story.fromJson(Map<String, dynamic> j) => Story(
        id: j['id'] as String,
        userId: j['userId'] as String,
        authorName: (j['authorName'] as String?) ?? 'Athlete',
        caption: j['caption'] as String?,
        imageUrl: j['imageUrl'] as String?,
        location: j['location'] as String?,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        likeCount: (j['likeCount'] as num?)?.toInt() ?? 0,
        likedByMe: j['likedByMe'] as bool? ?? false,
      );

  Story copyWith({int? likeCount, bool? likedByMe}) => Story(
        id: id,
        userId: userId,
        authorName: authorName,
        caption: caption,
        imageUrl: imageUrl,
        location: location,
        expiresAt: expiresAt,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
      );
}

/// An author's active stories, grouped for the tray bubble + viewer playback.
/// [stories] is ordered oldest → newest (IG playback order).
class StoryAuthorGroup {
  StoryAuthorGroup({
    required this.userId,
    required this.authorName,
    required this.stories,
    required this.isMe,
  });

  final String userId;
  final String authorName;
  final List<Story> stories;
  final bool isMe;

  /// Newest story — drives the tray bubble thumbnail.
  Story get newest => stories.last;

  /// First story image to show in the bubble (newest with a photo, else null).
  String? get thumbUrl {
    for (final s in stories.reversed) {
      if (s.imageUrl != null && s.imageUrl!.isNotEmpty) return s.imageUrl;
    }
    return null;
  }
}

/// Groups a newest-first feed into per-author playback groups. The viewer plays
/// each group's stories oldest→newest; the tray shows newest-author-first, with
/// the current user's own group pulled to the front.
List<StoryAuthorGroup> groupStoriesByAuthor(List<Story> feed, {String? meId}) {
  final order = <String>[];
  final byUser = <String, List<Story>>{};
  for (final s in feed) {
    (byUser[s.userId] ??= <Story>[]).add(s);
    if (!order.contains(s.userId)) order.add(s.userId);
  }
  final groups = order.map((uid) {
    final list = byUser[uid]!; // newest-first (feed order)
    return StoryAuthorGroup(
      userId: uid,
      authorName: list.first.authorName,
      stories: list.reversed.toList(growable: false), // oldest → newest
      isMe: meId != null && uid == meId,
    );
  }).toList();
  // Own group first; everyone else keeps newest-author-first order.
  groups.sort((a, b) {
    if (a.isMe == b.isMe) return 0;
    return a.isMe ? -1 : 1;
  });
  return groups;
}

/// Typed error so the UI can tell auth/network/server apart.
class StoriesException implements Exception {
  StoriesException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get isAuthError => statusCode == 401 || statusCode == 403;
  @override
  String toString() => 'StoriesException($message, status=$statusCode)';
}

class StoriesService {
  StoriesService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getAccessToken();
    if (token == null) throw StoriesException('Not signed in', statusCode: 401);
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// GET /v1/stories/feed — own + accepted-friends' active stories, newest first.
  Future<List<Story>> getFeed() async {
    final headers = await _headers();
    final http.Response res;
    try {
      res = await http
          .get(Uri.parse('$v1Base/stories/feed'), headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw StoriesException('Network error');
    }
    if (res.statusCode != 200) {
      throw StoriesException('Failed to load stories', statusCode: res.statusCode);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['data'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Story.fromJson)
        .toList(growable: false);
  }

  /// POST /v1/stories — create a 24h story. Returns the created story.
  Future<Story> createStory({
    String? caption,
    String? location,
    Uint8List? imageBytes,
  }) async {
    final headers = await _headers();
    final body = <String, dynamic>{};
    final cap = caption?.trim();
    if (cap != null && cap.isNotEmpty) body['caption'] = cap;
    final loc = location?.trim();
    if (loc != null && loc.isNotEmpty) body['location'] = loc;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      body['imageBase64'] = imageBytes.length > _kIsolateEncodeThresholdBytes
          ? await compute(_encodeBytesToBase64, imageBytes)
          : base64Encode(imageBytes);
    }
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('$v1Base/stories'),
              headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw StoriesException('Network error');
    }
    if (res.statusCode != 201) {
      throw StoriesException('Failed to create story', statusCode: res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Story.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// POST /v1/stories/:id/like — toggle heart. Returns the new (liked, count).
  Future<({bool liked, int likeCount})> toggleLike(String storyId) async {
    final headers = await _headers();
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('$v1Base/stories/$storyId/like'), headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw StoriesException('Network error');
    }
    if (res.statusCode != 200) {
      throw StoriesException('Failed to like story', statusCode: res.statusCode);
    }
    final data =
        (jsonDecode(res.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return (
      liked: data['liked'] as bool? ?? false,
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// DELETE /v1/stories/:id — owner only.
  Future<void> deleteStory(String storyId) async {
    final headers = await _headers();
    final http.Response res;
    try {
      res = await http
          .delete(Uri.parse('$v1Base/stories/$storyId'), headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw StoriesException('Network error');
    }
    if (res.statusCode != 204) {
      throw StoriesException('Failed to delete story', statusCode: res.statusCode);
    }
  }
}
