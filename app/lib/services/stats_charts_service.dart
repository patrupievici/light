import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import 'app_data_cache.dart';
import 'auth_service.dart';
import 'http_client.dart';

class WeeklyEffortPoint {
  WeeklyEffortPoint({required this.weekStart, required this.volumeKg, required this.workSets});
  final String weekStart;
  final double volumeKg;
  final int workSets;

  static WeeklyEffortPoint fromJson(Map<String, dynamic> j) => WeeklyEffortPoint(
        weekStart: j['weekStart'] as String,
        volumeKg: (j['volumeKg'] as num).toDouble(),
        workSets: (j['workSets'] as num).toInt(),
      );
}

class DailyTrainingPoint {
  DailyTrainingPoint({
    required this.day,
    required this.sessions,
    required this.volumeKg,
    required this.workSets,
  });
  final String day;
  final int sessions;
  final double volumeKg;
  final int workSets;

  static DailyTrainingPoint fromJson(Map<String, dynamic> j) => DailyTrainingPoint(
        day: j['day'] as String,
        sessions: (j['sessions'] as num).toInt(),
        volumeKg: (j['volumeKg'] as num).toDouble(),
        workSets: (j['workSets'] as num).toInt(),
      );
}

class WeeklySessionsPoint {
  WeeklySessionsPoint({required this.weekStart, required this.sessions});
  final String weekStart;
  final int sessions;

  static WeeklySessionsPoint fromJson(Map<String, dynamic> j) => WeeklySessionsPoint(
        weekStart: j['weekStart'] as String,
        sessions: (j['sessions'] as num).toInt(),
      );
}

class TopExercisePoint {
  TopExercisePoint({
    required this.exerciseId,
    required this.name,
    required this.volumeKg,
    required this.workSets,
  });
  final String exerciseId;
  final String name;
  final double volumeKg;
  final int workSets;

  static TopExercisePoint fromJson(Map<String, dynamic> j) => TopExercisePoint(
        exerciseId: j['exerciseId'] as String,
        name: j['name'] as String,
        volumeKg: (j['volumeKg'] as num).toDouble(),
        workSets: (j['workSets'] as num).toInt(),
      );
}

class CumulativeVolumePoint {
  CumulativeVolumePoint({
    required this.day,
    required this.dailyVolumeKg,
    required this.cumulativeVolumeKg,
  });
  /// `YYYY-MM-DD` (UTC).
  final String day;
  final double dailyVolumeKg;
  final double cumulativeVolumeKg;

  static CumulativeVolumePoint fromJson(Map<String, dynamic> j) => CumulativeVolumePoint(
        day: j['day'] as String,
        dailyVolumeKg: (j['dailyVolumeKg'] as num).toDouble(),
        cumulativeVolumeKg: (j['cumulativeVolumeKg'] as num).toDouble(),
      );
}

class CumulativeVolumeYear {
  CumulativeVolumeYear({
    required this.year,
    required this.totalKg,
    required this.activeDays,
    required this.points,
  });
  final int year;
  final double totalKg;
  final int activeDays;
  final List<CumulativeVolumePoint> points;
}

class RecentPr {
  RecentPr({
    required this.exerciseId,
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
    required this.previousBestKg,
    required this.date,
  });
  final String exerciseId;
  final String exerciseName;
  final double weightKg;
  final int reps;
  /// 0 when this is the user's first ever set at this rep count.
  final double previousBestKg;
  /// ISO-8601 UTC string from the server.
  final String date;

  /// Human label for the PR row, e.g. "5RM: 100 → 102.5 kg".
  String get headline {
    final next = weightKg.toStringAsFixed(weightKg % 1 == 0 ? 0 : 1);
    if (previousBestKg <= 0) {
      return 'First ${reps}RM: $next kg';
    }
    final prev = previousBestKg.toStringAsFixed(previousBestKg % 1 == 0 ? 0 : 1);
    return '${reps}RM: $prev → $next kg';
  }

  double get deltaKg => weightKg - previousBestKg;

  static RecentPr fromJson(Map<String, dynamic> j) => RecentPr(
        exerciseId: j['exerciseId'] as String,
        exerciseName: j['exerciseName'] as String,
        weightKg: (j['weightKg'] as num).toDouble(),
        reps: (j['reps'] as num).toInt(),
        previousBestKg: (j['previousBestKg'] as num).toDouble(),
        date: j['date'] as String,
      );
}

class RankLpPoint {
  RankLpPoint({
    required this.exerciseId,
    required this.name,
    required this.lpTotal,
    required this.bestE1rmKg,
  });
  final String exerciseId;
  final String name;
  final int lpTotal;
  final double bestE1rmKg;

  static RankLpPoint fromJson(Map<String, dynamic> j) => RankLpPoint(
        exerciseId: j['exerciseId'] as String,
        name: j['name'] as String,
        lpTotal: (j['lpTotal'] as num).toInt(),
        bestE1rmKg: (j['bestE1rmKg'] as num).toDouble(),
      );
}

/// GET /v1/me/stats/*
class StatsChartsService {
  StatsChartsService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() => authedReadHeaders(auth: _auth);

  /// Cache-first fetch of a stats endpoint, generic over the cached payload.
  ///
  /// Decodes the response, picks the cacheable payload via [extract], stores it,
  /// and maps it to [T] via [parse]. Serves cache within [ttl] (gated by [isMap]
  /// — Map-shape payloads check `value is Map`, list-shape check `value is List`),
  /// skips the network unless [refresh], and falls back to stale cache on error —
  /// so the Progress tab + detail screens render instantly and stop re-requesting.
  Future<T> _cachedJson<T>(
    String path,
    Map<String, String> query,
    String cacheKey, {
    required bool refresh,
    required Object Function(Map<String, dynamic> body) extract,
    required T Function(Object? payload) parse,
    Duration ttl = const Duration(hours: 2),
    bool isMap = false,
  }) async {
    bool cacheable(Object? v) => isMap ? v is Map : v is List;
    if (!refresh) {
      final c = await AppDataCache.instance.getTimed(cacheKey);
      if (c != null && c.age < ttl && cacheable(c.value)) return parse(c.value);
    }
    try {
      final res = await http.get(
        Uri.parse('$v1Base$path')
            .replace(queryParameters: query.isEmpty ? null : query),
        headers: await _headers(),
      ).withTimeout();
      if (res.statusCode != 200) throw Exception('Stats ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final payload = extract(data);
      await AppDataCache.instance.putTimedJson(cacheKey, payload);
      return parse(payload);
    } catch (e) {
      final c = await AppDataCache.instance.getTimed(cacheKey);
      if (c != null && cacheable(c.value)) return parse(c.value);
      rethrow;
    }
  }

  /// Cache-first fetch of a `{data:[...]}` stats endpoint. Returns the raw
  /// list (each caller maps to its type). Delegates to [_cachedJson].
  Future<List<dynamic>> _cachedListData(
    String path,
    Map<String, String> query,
    String cacheKey, {
    required bool refresh,
    Duration ttl = const Duration(hours: 2),
  }) =>
      _cachedJson<List<dynamic>>(
        path,
        query,
        cacheKey,
        refresh: refresh,
        ttl: ttl,
        extract: (data) => data['data'] as List<dynamic>? ?? [],
        parse: (payload) => payload as List<dynamic>,
      );

  Future<List<WeeklyEffortPoint>> getWeeklyEffort(
      {int weeks = 12, bool refresh = false}) async {
    final list = await _cachedListData('/me/stats/weekly-effort',
        {'weeks': '$weeks'}, 'weekly_effort_${weeks}w_v1', refresh: refresh);
    return list
        .map((e) => WeeklyEffortPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static List<DailyTrainingPoint> _dtFromList(Object? value) => [
        if (value is List)
          for (final e in value)
            DailyTrainingPoint.fromJson(Map<String, dynamic>.from(e as Map)),
      ];

  /// Cache-first (keyed by [days]): serves the last training-load series
  /// instantly and skips the network unless [refresh] or the cache is stale.
  /// Powers the Train heatmap + weekly progress + 30D trend off ONE fetch.
  Future<List<DailyTrainingPoint>> getDailyTraining(
          {int days = 42, bool refresh = false}) =>
      _cachedJson<List<DailyTrainingPoint>>(
        '/me/stats/daily-training',
        {'days': '$days'},
        AppDataCache.dailyTrainingKey(days),
        refresh: refresh,
        extract: (data) => data['data'] as List<dynamic>? ?? [],
        parse: _dtFromList,
      );

  Future<List<WeeklySessionsPoint>> getWeeklySessions(
      {int weeks = 12, bool refresh = false}) async {
    final list = await _cachedListData('/me/stats/weekly-sessions',
        {'weeks': '$weeks'}, 'weekly_sessions_${weeks}w_v1', refresh: refresh);
    return list
        .map((e) => WeeklySessionsPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<TopExercisePoint>> getTopExercises(
      {int days = 90, int limit = 10, bool refresh = false}) async {
    final list = await _cachedListData(
        '/me/stats/top-exercises',
        {'days': '$days', 'limit': '$limit'},
        'top_exercises_${days}d_${limit}_v1',
        refresh: refresh);
    return list
        .map((e) => TopExercisePoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<RankLpPoint>> getRankLp({int limit = 12, bool refresh = false}) async {
    final list = await _cachedListData('/me/stats/rank-lp', {'limit': '$limit'},
        'rank_lp_${limit}_v1', refresh: refresh);
    return list
        .map((e) => RankLpPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Year-long cumulative volume series for the hero chart.
  /// Defaults to the current UTC year when [year] is null.
  CumulativeVolumeYear _cvFromMap(Map<String, dynamic> data) => CumulativeVolumeYear(
        year: (data['year'] as num).toInt(),
        totalKg: (data['totalKg'] as num).toDouble(),
        activeDays: (data['activeDays'] as num).toInt(),
        points: (data['data'] as List<dynamic>? ?? [])
            .map((e) => CumulativeVolumePoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Future<CumulativeVolumeYear> getCumulativeVolume(
      {int? year, bool refresh = false}) {
    final params = <String, String>{};
    if (year != null) params['year'] = '$year';
    return _cachedJson<CumulativeVolumeYear>(
      '/me/stats/cumulative-volume',
      params,
      'cumulative_volume_${year ?? 'cur'}_v1',
      refresh: refresh,
      isMap: true,
      // Top-level year/totalKg map shape — cache the whole payload, not {data:[]}.
      extract: (data) => data,
      parse: (payload) => _cvFromMap(Map<String, dynamic>.from(payload as Map)),
    );
  }

  /// Rep-range PRs in the last [days]. Most recent first.
  Future<List<RecentPr>> getRecentPrs({int days = 30, bool refresh = false}) async {
    final list = await _cachedListData('/me/stats/recent-prs', {'days': '$days'},
        'recent_prs_${days}d_v1', refresh: refresh);
    return list
        .map((e) => RecentPr.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
