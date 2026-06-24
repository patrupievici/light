import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '_crash_reporter.dart';
import 'secure_db.dart';

/// Single rest-between-sets observation logged on-device.
///
/// "Rest" = wall-clock seconds between the moment a completed set was logged
/// and the moment the next set on the **same exercise** was logged. The first
/// set of an exercise has no preceding set, so no row is written for it.
///
/// Stored in `rest_intervals` table; see [RestIntervalStore._kCreateTable].
@immutable
class RestInterval {
  const RestInterval({
    required this.id,
    required this.exerciseId,
    required this.exerciseName,
    required this.workoutId,
    required this.setId,
    required this.restSeconds,
    required this.endedAt,
  });

  final int id;
  final String exerciseId;
  final String exerciseName;
  final String workoutId;
  final String setId;
  final int restSeconds;
  final DateTime endedAt;

  static RestInterval _fromRow(Map<String, dynamic> r) => RestInterval(
        id: r['id'] as int,
        exerciseId: r['exercise_id'] as String,
        exerciseName: (r['exercise_name'] as String?) ?? '',
        workoutId: r['workout_id'] as String,
        setId: r['set_id'] as String,
        restSeconds: r['rest_seconds'] as int,
        endedAt: DateTime.parse(r['ended_at'] as String),
      );
}

/// Pure comparison of an *actual* rest period against the *prescribed* rest for
/// a set (the exercise's `restSecondsDefault` / planned `restSeconds`).
///
/// Holds no state and touches nothing — it exists so the tracker can surface a
/// rest-timer prescription and so a future explainability line can read
/// "Rested 45s vs 90s prescribed" without re-deriving the comparison. The
/// tolerance band keeps trivial over/undershoots from reading as misses (a
/// human can't hit a target to the exact second).
@immutable
class RestAdherence {
  const RestAdherence({
    required this.actualSeconds,
    required this.prescribedSeconds,
  });

  /// Compare [actualSeconds] of observed rest against [prescribedSeconds].
  /// Negative actuals are clamped to 0 (defensive — wall-clock math should
  /// never produce one, but a row must never claim "rested -3s").
  factory RestAdherence.compare({
    required int actualSeconds,
    required int prescribedSeconds,
  }) =>
      RestAdherence(
        actualSeconds: actualSeconds < 0 ? 0 : actualSeconds,
        prescribedSeconds: prescribedSeconds,
      );

  final int actualSeconds;
  final int prescribedSeconds;

  /// Within ±[toleranceSeconds] of the prescription, treated as "on target".
  static const int toleranceSeconds = 10;

  /// actual − prescribed. Positive = rested longer than prescribed.
  int get deltaSeconds => actualSeconds - prescribedSeconds;

  /// True when there is a meaningful prescription to compare against. A zero or
  /// negative prescription means "no rest planned" → no adherence verdict.
  bool get hasPrescription => prescribedSeconds > 0;

  bool get withinTarget =>
      hasPrescription && deltaSeconds.abs() <= toleranceSeconds;

  bool get tooShort => hasPrescription && deltaSeconds < -toleranceSeconds;

  bool get tooLong => hasPrescription && deltaSeconds > toleranceSeconds;

  /// One-line explainability string, or null when there is nothing to explain
  /// (no prescription). Example: "Rested 45s vs 90s prescribed".
  String? get explainLine {
    if (!hasPrescription) return null;
    return 'Rested ${actualSeconds}s vs ${prescribedSeconds}s prescribed';
  }
}

/// Aggregated point used by [RestTimeTrendChart] — one bucket per workout
/// session ordered oldest → newest.
@immutable
class RestSessionPoint {
  const RestSessionPoint({
    required this.workoutId,
    required this.endedAt,
    required this.avgRestSeconds,
    required this.sampleCount,
  });
  final String workoutId;
  final DateTime endedAt;
  final double avgRestSeconds;
  final int sampleCount;
}

/// Client-only persistent log of rest periods. Backend has no equivalent yet
/// (CLAUDE.md P0.3): when/if rest sync ships, this becomes the offline cache.
class RestIntervalStore {
  RestIntervalStore._();
  static final RestIntervalStore instance = RestIntervalStore._();

  static const String _kDbName = 'zvelt_rest_intervals.db';
  static const String _kTable = 'rest_intervals';

  // Plausible rest window. Anything outside this is almost certainly a
  // backgrounded app / forgotten session — drop instead of corrupting the
  // trend. (5 s is faster than humans realistically rest; 30 min is longer
  // than any continuous lift.)
  static const int _kMinSeconds = 5;
  static const int _kMaxSeconds = 30 * 60;

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    // Wave 15 — encrypted via SQLCipher; ephemeral cache, recreate on failure.
    _db = await SecureDb.instance.openEncryptedOrRecreate(
      dbName: _kDbName,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_kTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercise_id TEXT NOT NULL,
            exercise_name TEXT NOT NULL DEFAULT '',
            workout_id TEXT NOT NULL,
            set_id TEXT NOT NULL UNIQUE,
            rest_seconds INTEGER NOT NULL,
            ended_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_rest_exercise ON $_kTable (exercise_id, ended_at)',
        );
        await db.execute(
          'CREATE INDEX idx_rest_workout ON $_kTable (workout_id, ended_at)',
        );
      },
    );
    return _db!;
  }

  /// Insert a rest sample. Out-of-band durations are dropped silently.
  /// Re-logging the same `setId` (e.g. user edits the set and re-logs) is a
  /// no-op thanks to the UNIQUE constraint + `IGNORE` conflict.
  Future<void> logRestInterval({
    required String exerciseId,
    required String exerciseName,
    required String workoutId,
    required String setId,
    required int restSeconds,
    required DateTime endedAt,
  }) async {
    if (restSeconds < _kMinSeconds || restSeconds > _kMaxSeconds) return;
    try {
      final db = await _open();
      await db.insert(
        _kTable,
        {
          'exercise_id': exerciseId,
          'exercise_name': exerciseName,
          'workout_id': workoutId,
          'set_id': setId,
          'rest_seconds': restSeconds,
          'ended_at': endedAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      debugPrint('[rest-store] insert failed: $e');
    }
  }

  /// All samples for an exercise, newest first. Used by future per-exercise
  /// drill-downs; current chart uses [recentSessionAverages].
  Future<List<RestInterval>> recentByExercise(
    String exerciseId, {
    int limit = 30,
  }) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        where: 'exercise_id = ?',
        whereArgs: [exerciseId],
        orderBy: 'ended_at DESC',
        limit: limit,
      );
      return rows.map(RestInterval._fromRow).toList();
    } catch (e) {
      debugPrint('[rest-store] query failed: $e');
      return const [];
    }
  }

  /// Mean rest for one exercise across all logged samples, or null if none.
  Future<double?> avgRestForExercise(String exerciseId) async {
    try {
      final db = await _open();
      final rows = await db.rawQuery(
        'SELECT AVG(rest_seconds) AS avg_rest FROM $_kTable WHERE exercise_id = ?',
        [exerciseId],
      );
      if (rows.isEmpty) return null;
      final v = rows.first['avg_rest'];
      if (v is num) return v.toDouble();
      return null;
    } catch (e) {
      debugPrint('[rest-store] avg query failed: $e');
      return null;
    }
  }

  /// One point per workout session, ordered oldest → newest, limited to the
  /// most recent [limit] sessions. Each point is the mean of every rest
  /// sample logged for that workout.
  Future<List<RestSessionPoint>> recentSessionAverages({int limit = 20}) async {
    try {
      final db = await _open();
      final rows = await db.rawQuery('''
        SELECT workout_id,
               MAX(ended_at) AS last_ended_at,
               AVG(rest_seconds) AS avg_rest,
               COUNT(*) AS n
        FROM $_kTable
        GROUP BY workout_id
        ORDER BY last_ended_at DESC
        LIMIT ?
      ''', [limit]);
      final points = rows.map((r) {
        return RestSessionPoint(
          workoutId: r['workout_id'] as String,
          endedAt: DateTime.parse(r['last_ended_at'] as String),
          avgRestSeconds: (r['avg_rest'] as num).toDouble(),
          sampleCount: (r['n'] as num).toInt(),
        );
      }).toList();
      // Reverse so the chart reads left-to-right as time progresses.
      return points.reversed.toList();
    } catch (e) {
      debugPrint('[rest-store] session aggregation failed: $e');
      return const [];
    }
  }

  /// Test-only / debug — wipe and recreate.
  @visibleForTesting
  Future<void> clearAll() async {
    try {
      final db = await _open();
      await db.delete(_kTable);
    } catch (e, st) {
      reportError(e, st, reason: 'rest-intervals:clear-all');
    }
  }
}
