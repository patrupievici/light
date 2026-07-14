import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import '../models/social_feed_post.dart';
import '_crash_reporter.dart';
import 'auth_service.dart';
import 'moderation_service.dart';

/// Wave 22 P0.1 — top-level helper so `compute()` can spawn it in an
/// isolate. base64Encode on a 1–5 MB image takes ~150–300 ms on a mid-
/// range Android phone, which is a clear jank source on the UI thread.
/// Called from [SocialFeedService.createPost] and the story-create
/// flow; only worth the isolate spawn for payloads > ~100 KB
/// (spawn cost is ~10 ms on Android, vs ~5 ms for inline encoding of
/// tiny thumbnails).
String _encodeBytesToBase64(Uint8List bytes) => base64Encode(bytes);

/// Threshold above which base64 encoding moves to an isolate. Below
/// this, inline is cheaper than spawn overhead.
const int _kIsolateEncodeThresholdBytes = 100 * 1024;

/// One page of feed results returned by [SocialFeedService.getFeedPage].
///
/// The backend `/feed` (and `/me/bookmarks`) endpoints are page/limit offset
/// APIs that return `{ data, meta:{page,limit} }` with NO cursor/total/hasMore.
/// So pagination is page-number based: [nextPage] is the page to request next
/// (`null` once the feed is exhausted), and [hasMore] is `true` while the
/// server returned a FULL page (raw length >= the requested limit). UI should
/// stop paginating when [hasMore] is `false`.
class SocialFeedPage {
  const SocialFeedPage({required this.posts, this.nextPage, this.hasMore = false});
  final List<SocialFeedPost> posts;
  final int? nextPage;
  final bool hasMore;
}

/// Typed error for [SocialFeedService] calls so the UI can distinguish
/// network failures from auth/server problems and render appropriate copy.
class SocialFeedException implements Exception {
  SocialFeedException(this.message, {this.statusCode, this.isNetworkError = false});
  final String message;
  final int? statusCode;
  final bool isNetworkError;

  bool get isAuthError => statusCode == 401 || statusCode == 403;
  bool get isServerError => statusCode != null && statusCode! >= 500;

  @override
  String toString() => 'SocialFeedException($message, status=$statusCode, network=$isNetworkError)';
}

class SocialFeedService {
  SocialFeedService({AuthService? auth, ModerationService? moderation})
      : _auth = auth ?? AuthService(),
        _moderation = moderation ?? ModerationService();
  final AuthService _auth;
  final ModerationService _moderation;

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getAccessToken();
    if (token == null) {
      throw SocialFeedException('Not signed in', statusCode: 401);
    }
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// Dispatches an HTTP request and maps the three transport exceptions to
  /// [SocialFeedException] with identical messages/flags to the previous
  /// per-method catch blocks. [headers] are built by the caller via
  /// [_headers] (which can throw a 401 — that MUST happen outside this
  /// try/catch). [timeout] is per-call: pass `null` to apply none (e.g.
  /// [createPost]).
  Future<http.Response> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async {
    try {
      Future<http.Response> dispatch;
      switch (method) {
        case 'POST':
          dispatch = http.post(uri, headers: headers, body: body);
          break;
        case 'GET':
        default:
          dispatch = http.get(uri, headers: headers);
          break;
      }
      return await (timeout == null ? dispatch : dispatch.timeout(timeout));
    } on SocketException catch (e) {
      throw SocialFeedException('Network unavailable: ${e.message}', isNetworkError: true);
    } on TimeoutException {
      throw SocialFeedException('Request timed out', isNetworkError: true);
    } on http.ClientException catch (e) {
      throw SocialFeedException('Network error: ${e.message}', isNetworkError: true);
    }
  }

  /// Best-effort decode of an error response body to a JSON map, or `null`
  /// when the body is absent/non-object/malformed. Mirrors the duplicated
  /// decode blocks in the post-mutation methods; [tag] names the caller for
  /// the debug log.
  Map<String, dynamic>? _decodeErrBody(String responseBody, {required String tag}) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (e) {
      debugPrint('[SocialFeedService.$tag] error-body decode best-effort skip: $e');
    }
    return null;
  }

  /// Convenience over [_decodeErrBody] for callers that only need the
  /// `message` field with a [fallback].
  String _decodeErrMessage(String responseBody, {required String tag, required String fallback}) {
    final err = _decodeErrBody(responseBody, tag: tag);
    return err?['message'] as String? ?? fallback;
  }

  /// Page/limit feed pagination matching the backend `/v1/posts/feed`
  /// (`{ data, meta:{page,limit} }`, no cursor). Pass [page] = 1 for the first
  /// page; follow `nextPage` from the returned [SocialFeedPage] to load more,
  /// and stop once `hasMore` is `false`.
  ///
  /// Optional filter params ([sort], [scope], [kind]) are forwarded as query
  /// params. The `/feed` route currently IGNORES them (only page/limit are
  /// read) and falls back to an unfiltered feed — these are future-proofing
  /// for when filtering ships server-side; behavior degrades cleanly to "no
  /// filter" until then.
  ///
  /// - [sort]: 'recent' (default) | 'popular' | 'trending'
  /// - [scope]: 'all' (default) | 'following' | 'friends'
  /// - [kind]: null (default) | 'race' (only race-tagged posts)
  ///
  /// End-of-feed is inferred from page size: a full page (raw server length >=
  /// [limit]) means there may be more; a short/empty page means the feed is
  /// exhausted. `hasMore` uses the RAW server list length BEFORE the
  /// client-side blocked-user filter so filtering a few rows can't falsely
  /// end the feed.
  Future<SocialFeedPage> getFeedPage({
    int page = 1,
    int limit = 20,
    String? sort,
    String? scope,
    String? kind,
  }) async {
    final headers = await _headers();
    final qp = <String, String>{'page': '$page', 'limit': '$limit'};
    if (sort != null && sort.isNotEmpty) qp['sort'] = sort;
    if (scope != null && scope.isNotEmpty) qp['scope'] = scope;
    if (kind != null && kind.isNotEmpty) qp['kind'] = kind;
    final uri = Uri.parse('$v1Base/posts/feed').replace(queryParameters: qp);
    debugPrint('[SocialFeedService.getFeedPage] GET $uri');
    final res = await _send('GET', uri, headers: headers, timeout: AuthService.httpTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SocialFeedException(
        'Feed request failed (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final posts = (data['data'] as List<dynamic>? ?? [])
          .map((p) => SocialFeedPost.fromJson(p as Map<String, dynamic>))
          .toList();
      // End-of-feed from RAW server page length, BEFORE the blocked filter, so
      // dropping a few blocked authors out of a full page can't prematurely
      // end the feed while the server still has more.
      final hasMore = posts.length >= limit;
      final nextPage = hasMore ? page + 1 : null;
      // Defense-in-depth: filter out blocked users client-side so the feed
      // stays clean even when backend enforcement is missing or delayed.
      final blocked = await _moderation.getCachedBlockedIds();
      final filtered = blocked.isEmpty
          ? posts
          : posts.where((p) => !blocked.contains(p.userId)).toList();
      return SocialFeedPage(posts: filtered, nextPage: nextPage, hasMore: hasMore);
    } on FormatException catch (e) {
      throw SocialFeedException('Malformed feed response: ${e.message}', statusCode: res.statusCode);
    } catch (e) {
      throw SocialFeedException('Could not parse feed: $e', statusCode: res.statusCode);
    }
  }

  /// Backwards-compatible wrapper that returns just the first page of posts.
  /// New callers should prefer [getFeedPage] so they can paginate.
  Future<List<SocialFeedPost>> getFeed() async {
    final page = await getFeedPage();
    return page.posts;
  }

  /// GET /v1/me/bookmarks — paginated list of posts the current user saved.
  ///
  /// Returns the same `SocialFeedPage` shape as [getFeedPage] so the UI can
  /// reuse all existing rendering / pagination plumbing. Pass [page] = 1 for
  /// the first page; follow `nextPage` to paginate and stop on `hasMore`==false.
  ///
  /// Backend may not have shipped this endpoint yet — on 404 we return an
  /// empty page silently (so the UI can show its empty state instead of an
  /// error toast) and log a one-shot Crashlytics breadcrumb so we know the
  /// endpoint is still missing in the wild. All other failures throw
  /// [SocialFeedException] for consistency with the rest of this service.
  Future<SocialFeedPage> getBookmarks({int page = 1, int limit = 20}) async {
    final headers = await _headers();
    final qp = <String, String>{'page': '$page', 'limit': '$limit'};
    final uri = Uri.parse('$v1Base/me/bookmarks').replace(queryParameters: qp);
    debugPrint('[SocialFeedService.getBookmarks] GET $uri');
    final res = await _send('GET', uri, headers: headers, timeout: AuthService.httpTimeout);
    // 404 → endpoint not yet shipped server-side. Surface as empty page so the
    // UI can show its "no bookmarks yet" empty state instead of an error.
    if (res.statusCode == 404) {
      if (!_bookmarks404Reported) {
        _bookmarks404Reported = true;
        reportError(
          Exception('GET /v1/me/bookmarks 404'),
          StackTrace.current,
          reason: 'bookmarks:endpoint-missing',
        );
      }
      return const SocialFeedPage(posts: [], nextPage: null, hasMore: false);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SocialFeedException(
        'Bookmarks request failed (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final posts = (data['data'] as List<dynamic>? ?? [])
          .map((p) => SocialFeedPost.fromJson(p as Map<String, dynamic>))
          .toList();
      final hasMore = posts.length >= limit;
      final nextPage = hasMore ? page + 1 : null;
      final blocked = await _moderation.getCachedBlockedIds();
      final filtered = blocked.isEmpty
          ? posts
          : posts.where((p) => !blocked.contains(p.userId)).toList();
      return SocialFeedPage(posts: filtered, nextPage: nextPage, hasMore: hasMore);
    } on FormatException catch (e) {
      throw SocialFeedException('Malformed bookmarks response: ${e.message}', statusCode: res.statusCode);
    } catch (e) {
      throw SocialFeedException('Could not parse bookmarks: $e', statusCode: res.statusCode);
    }
  }

  // Process-lifetime flag so we only log "endpoint missing" once per launch
  // instead of spamming Crashlytics on every pull-to-refresh.
  static bool _bookmarks404Reported = false;

  Future<SocialFeedPost?> getPost(String postId) async {
    final headers = await _headers();
    final res = await _send(
      'GET',
      Uri.parse('$v1Base/posts/$postId'),
      headers: headers,
      timeout: AuthService.httpTimeout,
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = data['data'] as Map<String, dynamic>?;
    if (raw == null) return null;
    return SocialFeedPost.fromJson(raw);
  }

  /// POST /v1/posts/:id/likes — toggle like.
  ///
  /// Returns the new server-side `liked` state when the response body carries
  /// it (`{liked: bool}`); otherwise falls back to `null` so the caller can
  /// trust its optimistic state. Throws [SocialFeedException] on HTTP failure
  /// or network error — consistent with the rest of this file's pattern, so
  /// the UI can distinguish "server says no" from "we don't know" and revert
  /// the optimistic toggle cleanly.
  Future<bool?> toggleLike(String postId) async {
    final headers = await _headers();
    final res = await _send(
      'POST',
      Uri.parse('$v1Base/posts/$postId/likes'),
      headers: headers,
      timeout: AuthService.httpTimeout,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw SocialFeedException(
        'Could not update like (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    try {
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic> && data['liked'] is bool) {
        return data['liked'] as bool;
      }
    } catch (e, st) {
      // Body shape is optional — log but don't fail the toggle.
      reportError(e, st, reason: 'feed:toggle-like-decode');
    }
    return null;
  }

  /// Throws [SocialFeedException] on network failure / non-200, mirroring
  /// [toggleLike] — previously a SocketException propagated raw and the
  /// comments sheet spun forever with no retry.
  Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final headers = await _headers();
    final res = await _send(
      'GET',
      Uri.parse('$v1Base/posts/$postId/comments'),
      headers: headers,
      timeout: AuthService.httpTimeout,
    );
    if (res.statusCode != 200) {
      throw SocialFeedException(
        'Could not load comments (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    final data = jsonDecode(res.body);
    List<Map<String, dynamic>> all;
    if (data is List) {
      all = data.cast<Map<String, dynamic>>();
    } else if (data is Map && data['data'] is List) {
      all = (data['data'] as List).cast<Map<String, dynamic>>();
    } else {
      return [];
    }
    // Hide comments from blocked users — defense in depth.
    final blocked = await _moderation.getCachedBlockedIds();
    if (blocked.isEmpty) return all;
    return all.where((c) {
      final uid = c['userId'] as String?;
      return uid == null || !blocked.contains(uid);
    }).toList();
  }

  /// True on 2xx, false on a server rejection; throws [SocialFeedException]
  /// on network failure/timeout so the composer can reset and offer retry
  /// instead of leaving the send button disabled forever.
  Future<bool> addComment(String postId, String body) async {
    final headers = await _headers();
    final res = await _send(
      'POST',
      Uri.parse('$v1Base/posts/$postId/comments'),
      headers: headers,
      body: jsonEncode({'body': body}),
      timeout: AuthService.httpTimeout,
    );
    return res.statusCode == 200 || res.statusCode == 201;
  }

  /// POST /v1/posts — cu [workoutId] după antrenament; fără el = postare doar în feed (caption și/sau poză).
  Future<void> createPost({
    String? workoutId,
    String? caption,
    String visibility = 'friends',
    bool hideWeights = false,
    bool hideReps = false,
    Uint8List? photoBytes,
  }) async {
    final headers = await _headers();
    final body = <String, dynamic>{
      'visibility': visibility,
    };
    if (workoutId != null) {
      body['workoutId'] = workoutId;
      body['privacySettings'] = {
        'hideWeights': hideWeights,
        'hideReps': hideReps,
      };
    }
    final cap = caption?.trim();
    if (cap != null && cap.isNotEmpty) body['caption'] = cap;
    if (photoBytes != null && photoBytes.isNotEmpty) {
      // Wave 22 P0.1 — offload large base64 encodes to an isolate so the
      // UI thread isn't blocked while we serialize a multi-MB image.
      // Tiny thumbnails (< 100 KB) inline because spawn cost > encode cost.
      final encoded = photoBytes.length > _kIsolateEncodeThresholdBytes
          ? await compute(_encodeBytesToBase64, photoBytes)
          : base64Encode(photoBytes);
      body['photoBase64'] = encoded;
    }

    final res = await _send(
      'POST',
      Uri.parse('$v1Base/posts'),
      headers: headers,
      body: jsonEncode(body),
      timeout: AuthService.httpTimeout,
    );

    if (res.statusCode != 201) {
      final err = _decodeErrBody(res.body, tag: 'createPost');
      final code = err?['error'] as String?;
      var msg = err?['message'] as String? ?? 'Could not post (${res.statusCode})';
      if (code == 'VALIDATION_ERROR' && err?['details'] is Map<String, dynamic>) {
        final details = err!['details'] as Map<String, dynamic>;
        final fieldErrors = details['fieldErrors'];
        if (fieldErrors is Map && fieldErrors.isNotEmpty) {
          for (final v in fieldErrors.values) {
            if (v is List && v.isNotEmpty && v.first is String) {
              msg = v.first as String;
              break;
            }
          }
        }
      }
      if (code != null && code.isNotEmpty) {
        throw SocialFeedException(
          '$msg ($code)',
          statusCode: res.statusCode,
        );
      }
      throw SocialFeedException(msg, statusCode: res.statusCode);
    }
  }

  /// După complete workout — același endpoint; rangurile se calculează pe server doar dacă ai greutate în profil.
  Future<void> createWorkoutPost({
    required String workoutId,
    String? caption,
    String visibility = 'friends',
    bool hideWeights = false,
    bool hideReps = false,
    Uint8List? photoBytes,
  }) {
    return createPost(
      workoutId: workoutId,
      caption: caption,
      visibility: visibility,
      hideWeights: hideWeights,
      hideReps: hideReps,
      photoBytes: photoBytes,
    );
  }

  /// POST /v1/posts/:id/bookmark — toggle; returnează noua stare bookmarked.
  ///
  /// Throws [SocialFeedException] on non-2xx / network failure instead of
  /// returning false — `false` means 'server says NOT bookmarked', and
  /// conflating it with 'request failed' made BookmarksScreen animate rows
  /// away on 500s while the post was still bookmarked server-side.
  Future<bool> toggleBookmark(String postId) async {
    final headers = await _headers();
    final res = await _send(
      'POST',
      Uri.parse('$v1Base/posts/$postId/bookmark'),
      headers: headers,
      timeout: const Duration(seconds: 22),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw SocialFeedException(
        'Could not update bookmark (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['bookmarked'] as bool? ?? false;
    } catch (e, st) {
      reportError(e, st, reason: 'feed:toggle-bookmark-decode');
      return false;
    }
  }

  /// POST /v1/posts/:id/hide
  Future<void> hidePost(String postId) async {
    final headers = await _headers();
    final res = await http
        .post(
          Uri.parse('$v1Base/posts/$postId/hide'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_decodeErrMessage(
        res.body,
        tag: 'hidePost',
        fallback: 'Could not hide post (${res.statusCode})',
      ));
    }
  }

  /// POST /v1/posts/:id/report
  Future<void> reportPost(String postId, {String? reason}) async {
    final headers = await _headers();
    final body = <String, dynamic>{};
    if (reason != null && reason.trim().isNotEmpty) body['reason'] = reason.trim();
    final res = await http
        .post(
          Uri.parse('$v1Base/posts/$postId/report'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_decodeErrMessage(
        res.body,
        tag: 'reportPost',
        fallback: 'Could not report post (${res.statusCode})',
      ));
    }
  }

  /// PATCH /v1/posts/:id — returnează post actualizat sau null la eroare.
  Future<SocialFeedPost?> editPost(String postId, {String? caption, String? visibility}) async {
    final headers = await _headers();
    final body = <String, dynamic>{};
    if (caption != null) body['caption'] = caption;
    if (visibility != null) body['visibility'] = visibility;
    final res = await http
        .patch(
          Uri.parse('$v1Base/posts/$postId'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 200) return null;
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = data['data'] as Map<String, dynamic>?;
      if (raw == null) return null;
      return SocialFeedPost.fromJson(raw);
    } catch (e, st) {
      reportError(e, st, reason: 'feed:edit-post-decode');
      return null;
    }
  }

  /// DELETE /v1/posts/:id — aruncă exception la eroare.
  Future<void> deletePost(String postId) async {
    final headers = await _headers();
    final res = await http
        .delete(
          Uri.parse('$v1Base/posts/$postId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_decodeErrMessage(
        res.body,
        tag: 'deletePost',
        fallback: 'Could not delete post (${res.statusCode})',
      ));
    }
  }
}
