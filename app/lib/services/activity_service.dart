import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart' show v1Base;
import '../models/game_xp_models.dart';
import 'auth_service.dart';
import 'http_client.dart';

/// Server rejected the activity payload (4xx) — retrying the same payload will
/// never succeed, so callers must NOT queue it for offline replay.
class ActivitySaveException implements Exception {
  ActivitySaveException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

/// The persisted GPS activity as returned by POST /v1/activities (201).
/// When route_points were usable the server RECOMPUTES distance/duration
/// (anti-cheat) — treat these as the source of truth over local estimates.
class SavedActivity {
  const SavedActivity({
    required this.id,
    this.distanceM,
    this.durationS,
    this.recomputed = false,
  });

  final String id;
  final double? distanceM;
  final int? durationS;
  final bool recomputed;

  factory SavedActivity.fromJson(Map<String, dynamic> j) => SavedActivity(
        id: j['id'] as String? ?? '',
        distanceM: (j['distanceM'] as num?)?.toDouble(),
        durationS: (j['durationS'] as num?)?.toInt(),
        recomputed: j['recomputed'] as bool? ?? false,
      );
}

class XpBreakdownLine {
  const XpBreakdownLine({
    required this.label,
    required this.pct,
    required this.mult,
    required this.xp,
    this.detail,
  });

  final String label;
  final int pct;
  final int mult;
  final int xp;
  final String? detail;

  factory XpBreakdownLine.fromJson(Map<String, dynamic> j) => XpBreakdownLine(
        label: j['label'] as String? ?? '',
        pct: (j['pct'] as num?)?.toInt() ?? 0,
        mult: (j['mult'] as num?)?.toInt() ?? 1,
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        detail: j['detail'] as String?,
      );
}

class CardioCompleteResult {
  const CardioCompleteResult({
    required this.xpGain,
    this.gameXp,
    this.pctOfWr = 0,
    this.breakdown = const [],
  });

  final int xpGain;
  final GameXpSnapshot? gameXp;
  final int pctOfWr;
  final List<XpBreakdownLine> breakdown;

  factory CardioCompleteResult.fromJson(Map<String, dynamic> j) {
    final raw = j['xpBreakdown'];
    final lines = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => XpBreakdownLine.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <XpBreakdownLine>[];
    return CardioCompleteResult(
      xpGain: (j['xpGain'] as num?)?.toInt() ?? 0,
      gameXp: j['gameXp'] is Map<String, dynamic>
          ? GameXpSnapshot.fromJson(j['gameXp'] as Map<String, dynamic>)
          : null,
      pctOfWr: (j['pctOfWr'] as num?)?.toInt() ?? (lines.isNotEmpty ? lines.first.pct : 0),
      breakdown: lines,
    );
  }
}

/// Cardio XP + calendar-related activity API.
class ActivityService {
  ActivityService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() => authedJsonHeaders(auth: _auth);

  /// Canonical wire shape for a recorded route: `[{lat, lng, t}]` where `t` is
  /// **epoch milliseconds** — the backend's normalizeRoutePoints drops ISO
  /// strings, so an ISO `ts` here would silently lose all timestamps (and with
  /// them server-side moving-time/pace).
  static List<Map<String, dynamic>> routePointsFrom(
    List<LatLng> points,
    List<DateTime> pointTs,
  ) =>
      [
        for (var i = 0; i < points.length; i++)
          {
            'lat': points[i].latitude,
            'lng': points[i].longitude,
            if (i < pointTs.length) 't': pointTs[i].millisecondsSinceEpoch,
          },
      ];

  /// POST /v1/activities — persist a completed GPS session (snake_case body).
  /// The server recomputes metrics from route_points when present and prefers
  /// the started_at→ended_at span for duration. Throws [ActivitySaveException]
  /// on 4xx (do not retry); network/5xx errors propagate for offline queueing.
  Future<SavedActivity> saveActivity({
    required List<Map<String, dynamic>> routePoints,
    required double distanceM,
    required int durationS,
    int? calories,
    String visibility = 'private',
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/activities'),
          headers: await _headers(),
          body: jsonEncode({
            'route_points': routePoints,
            'distance_m': distanceM,
            'duration_s': durationS,
            if (calories != null && calories > 0) 'calories': calories,
            'visibility': visibility,
            'started_at': startedAt.toUtc().toIso8601String(),
            'ended_at': endedAt.toUtc().toIso8601String(),
          }),
        )
        .withTimeout();
    if (res.statusCode == 200 || res.statusCode == 201) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final activity = j['activity'];
      return SavedActivity.fromJson(
          activity is Map<String, dynamic> ? activity : j);
    }
    String msg = 'Could not save activity (${res.statusCode})';
    try {
      final d = jsonDecode(res.body);
      if (d is Map && d['message'] != null) msg = d['message'] as String;
    } catch (_) {}
    if (res.statusCode >= 400 && res.statusCode < 500) {
      throw ActivitySaveException(res.statusCode, msg);
    }
    throw Exception(msg); // 5xx — transient, caller may queue for replay
  }

  /// POST /v1/activities/cardio/complete
  Future<CardioCompleteResult> completeCardio({
    required String mode,
    required double distanceM,
    required int durationSec,
    String source = 'app',
  }) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/activities/cardio/complete'),
          headers: await _headers(),
          body: jsonEncode({
            'mode': mode,
            'distanceM': distanceM,
            'durationSec': durationSec,
            'source': source,
          }),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      if (d is Map && d['message'] != null) throw Exception(d['message']);
      throw Exception('Could not award cardio XP (${res.statusCode})');
    }
    return CardioCompleteResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
