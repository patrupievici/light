import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart' show v1Base;
import '_crash_reporter.dart';
import 'auth_service.dart';
import 'http_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MUSCLE STATE
// ─────────────────────────────────────────────────────────────────────────────

enum MuscleState {
  untrained,   // never logged
  recovering,  // trained, still in recovery window
  ready,       // trained + fully recovered
}

class MuscleStatus {
  const MuscleStatus({
    required this.slug,
    required this.state,
    required this.lastTrainedAt,
    required this.recoveryHours,
    this.hoursRemaining = 0,
  });

  final String slug;
  final MuscleState state;
  final DateTime? lastTrainedAt;
  final int recoveryHours;
  final double hoursRemaining;

  String get label {
    switch (state) {
      case MuscleState.untrained: return 'Not trained';
      case MuscleState.recovering: return '${hoursRemaining.ceil()}h left';
      case MuscleState.ready: return 'Ready';
    }
  }
}

/// Per-muscle LEVEL (from GET /v1/me/muscle-levels): volume-RPG + strength.
/// Keyed by the same SVG slug as [MuscleStatus] so the map can pair them.
class MuscleLevel {
  const MuscleLevel({
    required this.slug,
    required this.level,
    required this.volumeXp,
    required this.volumeKg,
    required this.workSets,
    required this.bestLp,
    required this.tier,
    required this.lastTrainedAt,
  });

  final String slug;
  final int level;
  final int volumeXp, volumeKg, workSets, bestLp;
  final String tier;
  final DateTime? lastTrainedAt;

  static int _i(Object? v) => v is num ? v.toInt() : 0;

  static MuscleLevel fromJson(Map<String, dynamic> j) => MuscleLevel(
        slug: j['slug'] as String? ?? '',
        level: _i(j['level']),
        volumeXp: _i(j['volumeXp']),
        volumeKg: _i(j['volumeKg']),
        workSets: _i(j['workSets']),
        bestLp: _i(j['bestLp']),
        tier: j['tier'] as String? ?? 'Iron',
        lastTrainedAt: j['lastTrainedAt'] != null
            ? DateTime.tryParse(j['lastTrainedAt'] as String)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RECOVERY TIMES (hours) — based on NSCA guidelines
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, int> _recoveryHours = {
  'chest':      48,
  'deltoids':   48,
  'trapezius':  48,
  'biceps':     48,
  'triceps':    48,
  'forearm':    24,
  'abs':        24,
  'obliques':   24,
  'upper-back': 72,
  'lower-back': 72,
  'quadriceps': 72,
  'hamstring':  72,
  'gluteal':    72,
  'adductors':  48,
  'calves':     48,
  'tibialis':   24,
};

// Map from exercise primaryMuscle → SVG slug
const Map<String, String> _muscleToSlug = {
  'chest':       'chest',
  'back':        'upper-back',
  'shoulders':   'deltoids',
  'biceps':      'biceps',
  'triceps':     'triceps',
  'quads':       'quadriceps',
  'hamstrings':  'hamstring',
  'glutes':      'gluteal',
  'core':        'abs',
  'calves':      'calves',
  'forearms':    'forearm',
  'traps':       'trapezius',
  'lats':        'upper-back',
  'lower back':  'lower-back',
  'adductors':   'adductors',
  'fullbody': 'quadriceps', // Burpee etc. (seed uses fullBody → toLowerCase)
  'fullBody': 'quadriceps',
};

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class MuscleRecoveryService {
  MuscleRecoveryService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  /// Incrementat la [invalidateCache] — [MuscleMapWidget] se reîncarcă după workout.
  static final ValueNotifier<int> cacheRevision = ValueNotifier<int>(0);

  static const _cacheKeySuffix = 'muscle_recovery_cache';
  static const _cacheTtlMinutes = 30;

  /// SharedPreferences keys are always `${userId}_…` (or `anonymous_…` if logged out).
  Future<String> _prefsKey(String suffix) async {
    final userId = await _auth.getCurrentUserId();
    final prefix = userId ?? 'anonymous';
    return '${prefix}_$suffix';
  }

  /// Get recovery status for all muscle groups
  Future<Map<String, MuscleStatus>> getRecoveryStatus() async {
    // Try cache first
    final cached = await _loadCache();
    if (cached != null) return cached;

    // Fetch from backend
    final token = await _auth.getAccessToken();
    if (token == null) return _emptyStatus();

    try {
      // Get recent workouts (last 7 days)
      final res = await http.get(
        Uri.parse('$v1Base/workouts?limit=20'),
        headers: {'Authorization': 'Bearer $token'},
      ).withTimeout();
      if (res.statusCode != 200) return _emptyStatus();

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final workouts = (data['data'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      // Build last-trained map per muscle slug
      final Map<String, DateTime> lastTrained = {};

      for (final workout in workouts) {
        final endedAt = workout['endedAt'] as String?;
        if (endedAt == null) continue;
        final dt = DateTime.parse(endedAt).toLocal();

        // Only consider workouts from last 7 days
        if (DateTime.now().difference(dt).inDays > 7) continue;

        final exercises = workout['exercises'] as List<dynamic>? ?? [];
        for (final we in exercises) {
          final exercise = we['exercise'] as Map<String, dynamic>?;
          if (exercise == null) continue;
          final raw = exercise['primaryMuscle'] ?? exercise['primary_muscle'];
          final primaryMuscle = raw?.toString();
          if (primaryMuscle == null || primaryMuscle.isEmpty) continue;

          final key = primaryMuscle.toLowerCase().trim();
          final slug = _muscleToSlug[key] ?? _muscleToSlug[primaryMuscle];
          if (slug == null) continue;

          // Keep most recent
          if (!lastTrained.containsKey(slug) ||
              dt.isAfter(lastTrained[slug]!)) {
            lastTrained[slug] = dt;
          }
        }
      }

      // Build status map
      final status = _buildStatus(lastTrained);
      await _saveCache(status);
      return status;
    } catch (e, st) {
      reportError(e, st, reason: 'recovery:build-status');
      return _emptyStatus();
    }
  }

  Map<String, MuscleStatus> _buildStatus(Map<String, DateTime> lastTrained) {
    final now = DateTime.now();
    final result = <String, MuscleStatus>{};

    for (final slug in _recoveryHours.keys) {
      final recoveryH = _recoveryHours[slug]!;
      final lastDt = lastTrained[slug];

      if (lastDt == null) {
        result[slug] = MuscleStatus(
          slug: slug,
          state: MuscleState.untrained,
          lastTrainedAt: null,
          recoveryHours: recoveryH,
        );
        continue;
      }

      final hoursSince = now.difference(lastDt).inMinutes / 60.0;
      final hoursLeft = recoveryH - hoursSince;

      if (hoursLeft > 0) {
        result[slug] = MuscleStatus(
          slug: slug,
          state: MuscleState.recovering,
          lastTrainedAt: lastDt,
          recoveryHours: recoveryH,
          hoursRemaining: hoursLeft,
        );
      } else {
        result[slug] = MuscleStatus(
          slug: slug,
          state: MuscleState.ready,
          lastTrainedAt: lastDt,
          recoveryHours: recoveryH,
        );
      }
    }

    return result;
  }

  Map<String, MuscleStatus> _emptyStatus() {
    return {
      for (final slug in _recoveryHours.keys)
        slug: MuscleStatus(
          slug: slug,
          state: MuscleState.untrained,
          lastTrainedAt: null,
          recoveryHours: _recoveryHours[slug]!,
        ),
    };
  }

  Future<Map<String, MuscleStatus>?> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _prefsKey(_cacheKeySuffix);
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.parse(j['ts'] as String);
      if (DateTime.now().difference(ts).inMinutes > _cacheTtlMinutes) {
        return null;
      }
      final data = j['data'] as Map<String, dynamic>;
      return data.map((k, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(k, MuscleStatus(
          slug: k,
          state: MuscleState.values[m['state'] as int],
          lastTrainedAt: m['lastTrained'] != null
              ? DateTime.parse(m['lastTrained'] as String)
              : null,
          recoveryHours: m['recoveryHours'] as int,
          hoursRemaining: (m['hoursRemaining'] as num).toDouble(),
        ));
      });
    } catch (e) {
      debugPrint('[MuscleRecovery._loadCache] best-effort skip: $e');
      return null;
    }
  }

  Future<void> _saveCache(Map<String, MuscleStatus> status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _prefsKey(_cacheKeySuffix);
      await prefs.setString(key, jsonEncode({
        'ts': DateTime.now().toIso8601String(),
        'data': status.map((k, v) => MapEntry(k, {
          'state': v.state.index,
          'lastTrained': v.lastTrainedAt?.toIso8601String(),
          'recoveryHours': v.recoveryHours,
          'hoursRemaining': v.hoursRemaining,
        })),
      }));
    } catch (e) {
      debugPrint('[MuscleRecovery._saveCache] best-effort skip: $e');
    }
  }

  /// Per-muscle levels (volume-RPG + strength), keyed by SVG slug. Trained
  /// muscles only by default. Returns {} on any error / signed-out.
  Future<Map<String, MuscleLevel>> getMuscleLevels({int? windowDays}) async {
    final token = await _auth.getAccessToken();
    if (token == null) return {};
    try {
      final qp = <String, String>{if (windowDays != null) 'window': '$windowDays'};
      final uri = Uri.parse('$v1Base/me/muscle-levels')
          .replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).withTimeout();
      if (res.statusCode != 200) return {};
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
      final out = <String, MuscleLevel>{};
      for (final e in data.whereType<Map>()) {
        final m = MuscleLevel.fromJson(Map<String, dynamic>.from(e));
        if (m.slug.isNotEmpty) out[m.slug] = m;
      }
      return out;
    } catch (e, st) {
      reportError(e, st, reason: 'muscle-levels:fetch');
      return {};
    }
  }

  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _prefsKey(_cacheKeySuffix);
    await prefs.remove(key);
    cacheRevision.value = cacheRevision.value + 1;
  }
}
