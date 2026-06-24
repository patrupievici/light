import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';
import 'http_client.dart';

/// Thin wrapper over the backend ExerciseDB proxy (`/v1/exercises/db/*`).
///
/// The RapidAPI key stays server-side. All responses are already cached
/// for 24h on the backend, but we also keep a short-lived in-memory cache
/// here to avoid round-trips when the user toggles between screens.
class ExerciseDbService {
  ExerciseDbService({AuthService? auth}) : _auth = auth ?? AuthService();

  final AuthService _auth;

  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _ttl = Duration(minutes: 10);

  /// Fuzzy search by exercise name. Returns up to a few candidates.
  Future<List<ExerciseDbItem>> searchByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const [];

    final queryTokens = trimmed
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    var results = await _fetchByName(trimmed);

    if (results.isEmpty && queryTokens.length >= 2) {
      for (var start = 1; start < queryTokens.length; start++) {
        final candidate = queryTokens.sublist(start).join(' ');
        results = await _fetchByName(candidate);
        if (results.isNotEmpty) break;
      }
    }

    if (results.isEmpty) {
      final fallbackTokens = queryTokens
          .where((t) => t.length >= 4)
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final token in fallbackTokens) {
        results = await _fetchByName(token);
        if (results.isNotEmpty) break;
      }
    }

    if (results.isEmpty) return const [];

    final scored = results.map((item) {
      final nameLower = item.name.toLowerCase();
      final score = queryTokens.where(nameLower.contains).length;
      return _ScoredItem(item, score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.map((s) => s.item).toList(growable: false);
  }

  Future<List<ExerciseDbItem>> _fetchByName(String name) async {
    final data = await _get('/exercises/db/name/${Uri.encodeComponent(name)}');
    final list = _asList(data);
    return list.map(ExerciseDbItem.fromJson).toList(growable: false);
  }

  Future<ExerciseDbItem?> getById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final data = await _get('/exercises/db/${Uri.encodeComponent(trimmed)}');
    if (data is Map<String, dynamic>) return ExerciseDbItem.fromJson(data);
    return null;
  }

  Future<dynamic> _get(String subPath) async {
    final cached = _cache[subPath];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.payload;
    }

    final uri = Uri.parse('$v1Base$subPath');
    final Map<String, String> headers;
    try {
      headers = await authedReadHeaders(auth: _auth);
    } catch (_) {
      throw ExerciseDbException('Not signed in', statusCode: 401);
    }
    final res = await http.get(uri, headers: headers).withTimeout();

    if (res.statusCode == 503) {
      throw ExerciseDbException(
        'Exercise reference library is not configured on the server.',
        statusCode: 503,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ExerciseDbException(
        'ExerciseDB ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }

    final decoded = jsonDecode(res.body);
    final payload =
        decoded is Map<String, dynamic> && decoded.containsKey('data')
            ? decoded['data']
            : decoded;

    _cache[subPath] = _CacheEntry(
      payload: payload,
      expiresAt: DateTime.now().add(_ttl),
    );
    return payload;
  }

  static List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }
    return const [];
  }
}

class _CacheEntry {
  _CacheEntry({required this.payload, required this.expiresAt});
  final dynamic payload;
  final DateTime expiresAt;
}

class _ScoredItem {
  _ScoredItem(this.item, this.score);
  final ExerciseDbItem item;
  final int score;
}

class ExerciseDbItem {
  ExerciseDbItem({
    required this.id,
    required this.name,
    required this.gifUrl,
    required this.bodyPart,
    required this.equipment,
    required this.target,
    required this.secondaryMuscles,
    required this.instructions,
  });

  factory ExerciseDbItem.fromJson(Map<String, dynamic> j) {
    List<String> strList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
      return const [];
    }

    final id = (j['id'] ?? '').toString();
    final apiGifUrl = (j['gifUrl'] ?? '').toString();
    final gifUrl = apiGifUrl.isNotEmpty
        ? apiGifUrl
        : (id.isNotEmpty ? '$v1Base/exercises/db/image/$id?resolution=180' : '');

    return ExerciseDbItem(
      id: id,
      name: (j['name'] ?? '').toString(),
      gifUrl: gifUrl,
      bodyPart: (j['bodyPart'] ?? '').toString(),
      equipment: (j['equipment'] ?? '').toString(),
      target: (j['target'] ?? '').toString(),
      secondaryMuscles: strList(j['secondaryMuscles']),
      instructions: strList(j['instructions']),
    );
  }

  final String id;
  final String name;
  final String gifUrl;
  final String bodyPart;
  final String equipment;
  final String target;
  final List<String> secondaryMuscles;
  final List<String> instructions;

  bool get hasGif => gifUrl.isNotEmpty;
}

class ExerciseDbException implements Exception {
  ExerciseDbException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ExerciseDbException($statusCode): $message';
}
