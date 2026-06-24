import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart' show v1Base;
import '../services/_crash_reporter.dart';
import '../services/auth_service.dart';
import '../services/http_client.dart';

// ─── DTOs ─────────────────────────────────────────────────────────────────────

class SegmentDto {
  const SegmentDto({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.polyline,
    required this.distanceM,
    required this.elevationGainM,
  });

  final String id;
  final String name;
  final LatLng start;
  final LatLng end;
  final List<LatLng> polyline;
  final double distanceM;
  final double elevationGainM;

  static SegmentDto? fromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    try {
      final id = j['id'] as String?;
      final name = j['name'] as String?;
      if (id == null || name == null) return null;

      LatLng parsePoint(dynamic p) {
        if (p is Map) {
          return LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          );
        }
        if (p is List && p.length >= 2) {
          return LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble());
        }
        throw const FormatException('bad point');
      }

      final start = parsePoint(j['start']);
      final end = parsePoint(j['end']);
      final rawPoly = j['polyline'] as List<dynamic>? ?? [];
      final poly = rawPoly.map(parsePoint).toList();

      return SegmentDto(
        id: id,
        name: name,
        start: start,
        end: end,
        polyline: poly.isEmpty ? [start, end] : poly,
        distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0,
        elevationGainM: (j['elevationGainM'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      debugPrint('[SegmentDto.fromJson] parse best-effort skip: $e');
      return null;
    }
  }
}

class SegmentEffortResult {
  const SegmentEffortResult({
    required this.segment,
    required this.elapsedSec,
    required this.rank,
    required this.isKom,
    required this.prBroken,
  });

  final SegmentDto segment;
  final int elapsedSec;
  final int rank;
  final bool isKom;
  final bool prBroken;

  String get formattedTime {
    final m = elapsedSec ~/ 60;
    final s = elapsedSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ─── Detector ─────────────────────────────────────────────────────────────────

/// Detects GPS segment starts and finishes during live outdoor tracking.
///
/// Lifecycle:
/// 1. Call [loadNearby] once when tracking starts (fetches segments within 5 km).
/// 2. Call [processPosition] on every GPS update — it fires snackbars + [onKom].
/// 3. Call [dispose] when tracking stops.
class SegmentDetector {
  SegmentDetector({AuthService? auth}) : _auth = auth ?? AuthService();

  final AuthService _auth;
  final List<SegmentDto> _segments = [];

  // segmentId → timestamp when user crossed the start line
  final Map<String, DateTime> _activeSegments = {};

  bool get hasSegments => _segments.isNotEmpty;
  int get segmentCount => _segments.length;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Fetches segments within [radiusM] metres of the given coordinates.
  /// Silently no-ops on network errors so it never crashes the tracking flow.
  Future<void> loadNearby(double lat, double lng, {double radiusM = 5000}) async {
    try {
      final token = await _auth.getAccessToken();
      if (token == null) return;
      final uri = Uri.parse('$v1Base/segments/nearby').replace(queryParameters: {
        'lat': lat.toStringAsFixed(6),
        'lng': lng.toStringAsFixed(6),
        'radius': radiusM.toStringAsFixed(0),
      });
      final res = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .withTimeout();
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      _segments
        ..clear()
        ..addAll(list.map(SegmentDto.fromJson).whereType<SegmentDto>());
    } catch (e, st) {
      reportError(e, st, reason: 'segments:load-nearby');
    }
  }

  /// Call on every GPS position update during active tracking.
  ///
  /// Checks proximity to all loaded segment start/end points and:
  /// - Marks segment as active when within 25 m of start.
  /// - Submits effort + shows completion snackbar when within 25 m of end.
  /// - Fires [onKom] callback when the effort earns the top rank.
  Future<void> processPosition(
    LatLng position, {
    required BuildContext context,
    void Function(SegmentEffortResult result)? onKom,
  }) async {
    if (_segments.isEmpty) return;

    for (final seg in _segments) {
      final distToStart = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        seg.start.latitude, seg.start.longitude,
      );
      final distToEnd = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        seg.end.latitude, seg.end.longitude,
      );

      // User entered start zone
      if (distToStart < 25 && !_activeSegments.containsKey(seg.id)) {
        _activeSegments[seg.id] = DateTime.now();
        continue;
      }

      // User reached end zone while segment was active
      if (distToEnd < 25 && _activeSegments.containsKey(seg.id)) {
        final startTime = _activeSegments.remove(seg.id)!;
        final elapsedSec = DateTime.now().difference(startTime).inSeconds;
        // Ignore ghost crossings (< 5 s = likely standing still at start/end)
        if (elapsedSec < 5) continue;

        unawaited(_submitEffort(
          segment: seg,
          elapsedSec: elapsedSec,
          context: context,
          onKom: onKom,
        ));
      }
    }
  }

  /// Clears all state. Call when tracking session ends.
  void dispose() {
    _activeSegments.clear();
    _segments.clear();
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  Future<void> _submitEffort({
    required SegmentDto segment,
    required int elapsedSec,
    required BuildContext context,
    void Function(SegmentEffortResult result)? onKom,
  }) async {
    int rank = 0;
    bool isKom = false;
    bool prBroken = false;

    try {
      final token = await _auth.getAccessToken();
      if (token == null) return;
      final res = await http
          .post(
            Uri.parse('$v1Base/segments/${segment.id}/efforts'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'elapsedSec': elapsedSec}),
          )
          .withTimeout();

      if (res.statusCode == 200 || res.statusCode == 201) {
        try {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          rank = (body['rank'] as num?)?.toInt() ?? 0;
          isKom = body['isKom'] as bool? ?? rank == 1;
          prBroken = body['prBroken'] as bool? ?? false;
        } catch (e) {
          debugPrint('[SegmentDetector._submitEffort] response decode best-effort skip: $e');
        }
      }
    } catch (e, st) {
      reportError(e, st, reason: 'segments:submit-effort');
    }

    if (!context.mounted) return;

    final result = SegmentEffortResult(
      segment: segment,
      elapsedSec: elapsedSec,
      rank: rank,
      isKom: isKom,
      prBroken: prBroken,
    );

    _showSnackBar(context, result);
    if (isKom) onKom?.call(result);
  }

  void _showSnackBar(BuildContext context, SegmentEffortResult result) {
    final rankLabel = result.rank > 0 ? ' · #${result.rank} pe leaderboard' : '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Text('🏁', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Segment completat!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${result.segment.name} • ${result.formattedTime}$rankLabel',
                    style: const TextStyle(
                      color: Color(0xFFA9B0C0),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (result.isKom) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB020),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'KOM 👑',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: const Color(0xFF18181B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
