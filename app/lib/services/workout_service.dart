import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart' show v1Base;
import '../models/game_xp_models.dart';
import 'activity_service.dart';
import 'app_data_cache.dart';
import 'auth_service.dart';
import 'http_client.dart';

/// SharedPreferences key holding the JSON snapshot of the active (in-progress)
/// workout so the client can offer to resume after a crash / force-kill.
/// QA P1.11.
const String kActiveWorkoutPrefsKey = 'zvelt_active_workout';

/// Snapshot persisted under [kActiveWorkoutPrefsKey].
class ActiveWorkoutPointer {
  const ActiveWorkoutPointer({
    required this.workoutId,
    required this.startedAt,
    this.label,
  });

  final String workoutId;
  final DateTime startedAt;
  final String? label;

  Map<String, dynamic> toJson() => {
        'workoutId': workoutId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        if (label != null) 'label': label,
      };

  static ActiveWorkoutPointer? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final id = j['workoutId'] as String?;
      final iso = j['startedAt'] as String?;
      if (id == null || iso == null) return null;
      return ActiveWorkoutPointer(
        workoutId: id,
        startedAt: DateTime.parse(iso),
        label: j['label'] as String?,
      );
    } catch (e) {
      debugPrint('[active-workout] parse failed: $e');
      return null;
    }
  }
}

/// Thrown when a set's weight/reps/rpe fall outside spec bounds (CLAUDE.md
/// "Validări obligatorii"). Distinct from network/Exception so callers can
/// surface a friendly inline error instead of a snack-bar.
class SetValidationException implements Exception {
  const SetValidationException(this.field, this.message);
  final String field;
  final String message;

  @override
  String toString() => 'SetValidationException($field): $message';
}

/// Auth-flavored error raised by [WorkoutService.getWorkoutCalendar] when the
/// access token is missing/expired so the UI can decide to silently retry vs
/// kick the user to sign-in. Other failures (network, 5xx, timeout) bubble as
/// plain [Exception] / [TimeoutException]; 404 is mapped to an empty list so
/// the calendar still renders against the local sqflite cache.
class CalendarAuthException implements Exception {
  const CalendarAuthException([this.message = 'Not signed in']);
  final String message;
  @override
  String toString() => 'CalendarAuthException($message)';
}

/// Thrown by [WorkoutService.getWorkoutHeatmap] for non-404 / non-success
/// responses so the UI can distinguish "backend not shipped yet" (handled
/// silently, empty grid) from "real failure" (inline note). 404 is mapped to
/// an empty map instead and never throws.
class HeatmapRequestException implements Exception {
  const HeatmapRequestException(this.statusCode,
      [this.message = 'Heatmap request failed']);
  final int statusCode;
  final String message;
  @override
  String toString() => 'HeatmapRequestException($statusCode): $message';
}

/// Raised by [WorkoutService.addSet] / [WorkoutService.updateSet] when the server
/// rejects a >2× weight jump (vs the recent personal max) with a 422
/// `WEIGHT_JUMP_REQUIRES_NOTE`. The UI catches this to prompt the user for a
/// justification note and retry the same call with `note:` supplied.
class WeightJumpNoteRequiredException implements Exception {
  const WeightJumpNoteRequiredException([
    this.message =
        'A weight far above your recent record needs a short note explaining it.',
  ]);
  final String message;
  @override
  String toString() => 'WeightJumpNoteRequiredException($message)';
}

/// Bounds per CLAUDE.md spec — keep in sync with backend validators.
const double kSetWeightMinKg = 0.0;
const double kSetWeightMaxKg = 500.0;
const int kSetRepsMin = 1;
const int kSetRepsMax = 50;
const double kSetRpeMin = 1.0;
const double kSetRpeMax = 10.0;

void _validateSetInputs({double? weightKg, int? reps, double? rpe}) {
  if (weightKg != null &&
      (weightKg.isNaN ||
          weightKg < kSetWeightMinKg ||
          weightKg > kSetWeightMaxKg)) {
    throw const SetValidationException(
      'weightKg',
      'Weight must be 0–500 kg',
    );
  }
  if (reps != null && (reps < kSetRepsMin || reps > kSetRepsMax)) {
    throw const SetValidationException('reps', 'Reps must be 1–50');
  }
  if (rpe != null && (rpe.isNaN || rpe < kSetRpeMin || rpe > kSetRpeMax)) {
    throw const SetValidationException('rpe', 'RPE must be 1.0–10.0');
  }
}

/// Workout & exercise API client.
class WorkoutService {
  WorkoutService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() => authedJsonHeaders(auth: _auth);

  /// POST /v1/workouts — create draft workout
  Future<WorkoutDto> createWorkout({String? label}) async {
    final rawLabel = label?.trim();
    final cleanLabel =
        rawLabel != null && rawLabel.isNotEmpty ? rawLabel : null;
    final body = <String, dynamic>{
      if (cleanLabel != null) 'label': cleanLabel,
    };
    final res = await http
        .post(
          Uri.parse('$v1Base/workouts'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .withTimeout();
    if (res.statusCode != 201) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final w = WorkoutDto.fromJson(data['workout'] as Map<String, dynamic>);
    await saveActiveWorkoutPointer(w, label: cleanLabel ?? 'Workout');
    return w;
  }

  /// GET /v1/workouts — list past workouts (non-draft)
  Future<WorkoutsResponse> getWorkouts({int page = 1, int limit = 20}) async {
    final res = await http
        .get(
          Uri.parse('$v1Base/workouts')
              .replace(queryParameters: {'page': '$page', 'limit': '$limit'}),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
    return WorkoutsResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// GET /v1/workouts/:id
  Future<WorkoutDto> getWorkout(String id) async {
    final res = await http
        .get(Uri.parse('$v1Base/workouts/$id'), headers: await _headers())
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return WorkoutDto.fromJson(data['workout'] as Map<String, dynamic>);
  }

  /// POST /v1/workouts/:id/exercises
  Future<WorkoutExerciseDto> addExercise(String workoutId, String exerciseId,
      {int? position}) async {
    final body = <String, dynamic>{'exerciseId': exerciseId};
    if (position != null) body['position'] = position;
    final res = await http
        .post(
          Uri.parse('$v1Base/workouts/$workoutId/exercises'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .withTimeout();
    if (res.statusCode != 201) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return WorkoutExerciseDto.fromJson(
        data['workoutExercise'] as Map<String, dynamic>);
  }

  /// POST /v1/workouts/:id/exercises/:weId/sets
  ///
  /// [clientSetId] is an idempotency token (UUID). Pass the SAME value on retry
  /// (e.g. flushing an offline queue entry) and the server will dedupe to the
  /// existing row instead of creating a duplicate.
  Future<WorkoutSetDto> addSet(
    String workoutId,
    String weId, {
    required double weightKg,
    required int reps,
    double? rpe,
    String tag = 'WORK',
    bool isCompleted = true,
    String? clientSetId,
    String? note,
  }) async {
    _validateSetInputs(weightKg: weightKg, reps: reps, rpe: rpe);
    final body = <String, dynamic>{
      'weightKg': weightKg,
      'reps': reps,
      'tag': tag,
      'isCompleted': isCompleted,
      if (rpe != null) 'rpe': rpe,
      if (clientSetId != null) 'clientSetId': clientSetId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    final res = await http
        .post(
          Uri.parse('$v1Base/workouts/$workoutId/exercises/$weId/sets'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .withTimeout();
    // Anti-cheat: a >2× jump vs the recent personal max is rejected until the
    // user attaches a justification note.
    if (res.statusCode == 422 && _isWeightJump(res)) {
      final msg = _messageOf(res);
      throw msg == null
          ? const WeightJumpNoteRequiredException()
          : WeightJumpNoteRequiredException(msg);
    }
    // 201 = created, 200 = idempotent replay (same clientSetId).
    if (res.statusCode != 201 && res.statusCode != 200) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return WorkoutSetDto.fromJson(data['set'] as Map<String, dynamic>);
  }

  /// PATCH /v1/workouts/:id/exercises/:weId/sets/:setId
  Future<WorkoutSetDto> updateSet(
    String workoutId,
    String weId,
    String setId, {
    double? weightKg,
    int? reps,
    double? rpe,
    bool? isCompleted,
    String? note,
  }) async {
    _validateSetInputs(weightKg: weightKg, reps: reps, rpe: rpe);
    final body = <String, dynamic>{
      if (weightKg != null) 'weightKg': weightKg,
      if (reps != null) 'reps': reps,
      if (rpe != null) 'rpe': rpe,
      if (isCompleted != null) 'isCompleted': isCompleted,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    if (body.isEmpty) {
      throw Exception('Nothing to update');
    }
    final res = await http
        .patch(
          Uri.parse('$v1Base/workouts/$workoutId/exercises/$weId/sets/$setId'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .withTimeout();
    // Anti-cheat: a >2× jump vs the prior weight needs a justification note.
    if (res.statusCode == 422 && _isWeightJump(res)) {
      final msg = _messageOf(res);
      throw msg == null
          ? const WeightJumpNoteRequiredException()
          : WeightJumpNoteRequiredException(msg);
    }
    if (res.statusCode != 200) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return WorkoutSetDto.fromJson(data['set'] as Map<String, dynamic>);
  }

  /// DELETE /v1/workouts/:id/exercises/:weId/sets/:setId — remove a set.
  ///
  /// 404 is treated as success: for a delete, "the set is already gone" IS the
  /// desired end state (e.g. an offline delete replayed after the row was
  /// removed from another device, or a retry after a response was lost).
  /// Server returns 204 on success.
  Future<void> deleteSet(String workoutId, String weId, String setId) async {
    final res = await http
        .delete(
          Uri.parse('$v1Base/workouts/$workoutId/exercises/$weId/sets/$setId'),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode == 404) return;
    if (res.statusCode < 200 || res.statusCode >= 300) _throw(res);
  }

  /// GET /v1/workouts/:id/insight — post-workout AI coach commentary.
  ///
  /// Returns null on any error (offline, AI disabled, model failure) so the
  /// completion screen can fall back to its existing UI without crashing.
  /// Backend caches per (user, workout) for 1h, so revisits are free.
  Future<String?> fetchPostWorkoutInsight(String workoutId) async {
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/workouts/$workoutId/insight'),
            headers: await _headers(),
          )
          .withAiTimeout();
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final text = (data['insight'] as String?)?.trim();
      return (text != null && text.isNotEmpty) ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// GET /v1/me/weekly-coach-read — AI summary of the user's last 7 days of
  /// training. Refreshes once per ISO week on the backend (cached server-side),
  /// so calling this multiple times in the same week is free.
  ///
  /// Returns null on any failure so the Progress tab card can hide cleanly.
  Future<String?> fetchWeeklyCoachRead({bool refresh = false}) async {
    const key = 'weekly_coach_read_v1';
    // Backend recomputes per ISO week; a 6h client TTL kills the refetch on
    // every Progress visit while staying same-day fresh.
    if (!refresh) {
      final c = await AppDataCache.instance.getTimed(key);
      if (c != null && c.age < const Duration(hours: 6) && c.value is String) {
        return c.value as String;
      }
    }
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/me/weekly-coach-read'),
            headers: await _headers(),
          )
          .withAiTimeout();
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final text = (data['read'] as String?)?.trim();
      if (text != null && text.isNotEmpty) {
        await AppDataCache.instance.putTimedJson(key, text);
        return text;
      }
      return null;
    } catch (_) {
      final c = await AppDataCache.instance.getTimed(key);
      return (c != null && c.value is String) ? c.value as String : null;
    }
  }

  /// POST /v1/workouts/:id/complete — awards game XP (gym_rpg formula) and returns snapshot.
  Future<CompleteWorkoutResult> completeWorkout(
    String workoutId, {
    DateTime? startedAt,
    DateTime? endedAt,
    String? timezone,
  }) async {
    final cleanTimezone = timezone?.trim();
    final body = <String, dynamic>{
      if (startedAt != null) 'startedAt': startedAt.toUtc().toIso8601String(),
      if (endedAt != null) 'endedAt': endedAt.toUtc().toIso8601String(),
      if (cleanTimezone != null && cleanTimezone.isNotEmpty)
        'timezone': cleanTimezone,
    };
    final res = await http
        .post(
          Uri.parse('$v1Base/workouts/$workoutId/complete'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final gx = data['gameXp'] as Map<String, dynamic>?;
    final rawBd = data['xpBreakdown'];
    final breakdown = rawBd is List
        ? rawBd
            .whereType<Map>()
            .map((e) => XpBreakdownLine.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <XpBreakdownLine>[];
    // Workout finished server-side — drop the resume pointer so we don't
    // re-prompt next launch (P1.11).
    await clearActiveWorkoutPointer(matchingId: workoutId);
    return CompleteWorkoutResult(
      workout: WorkoutDto.fromJson(data['workout'] as Map<String, dynamic>),
      xpGain: (data['xpGain'] as num?)?.toInt() ?? 0,
      ageMultiplier: (data['ageMultiplier'] as num?)?.toDouble() ?? 1.0,
      gameXp: gx != null ? GameXpSnapshot.fromJson(gx) : null,
      xpBreakdown: breakdown,
    );
  }

  /// DELETE /v1/workouts/:id — abandon a draft workout. Best-effort: any 2xx /
  /// 404 (already gone) clears the local pointer. Other errors surface so the
  /// caller can show a snackbar. P1.11.
  Future<void> discardWorkout(String workoutId) async {
    try {
      final res = await http
          .delete(
            Uri.parse('$v1Base/workouts/$workoutId'),
            headers: await _headers(),
          )
          .withTimeout();
      final ok = (res.statusCode >= 200 && res.statusCode < 300) ||
          res.statusCode == 404;
      if (!ok) {
        debugPrint(
            '[discardWorkout] non-ok status ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint(
          '[discardWorkout] network error (clearing pointer anyway): $e');
    } finally {
      await clearActiveWorkoutPointer(matchingId: workoutId);
    }
  }

  /// POST /v1/workouts/from-suggestion — creates draft with exercises from AI suggestion (DeepSeek).
  Future<WorkoutDto> createWorkoutFromSuggestion() async {
    final res = await http
        .post(
          Uri.parse('$v1Base/workouts/from-suggestion'),
          headers: await _headers(),
          body: '{}',
        )
        .withTimeout();
    if (res.statusCode == 422) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      throw Exception(
          body?['message'] ?? 'Could not build workout from your profile');
    }
    if (res.statusCode != 201) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final w = WorkoutDto.fromJson(data['workout'] as Map<String, dynamic>);
    await saveActiveWorkoutPointer(w, label: 'Suggested workout');
    return w;
  }

  // ─── Active-workout pointer (resume-after-kill, P1.11) ───────────────────

  /// Persist [workout] as the in-progress session. Called automatically by
  /// `createWorkout` / `createWorkoutFromSuggestion`; exposed for cases where
  /// a workout is created through an alternate code path (e.g., AI chat).
  static Future<void> saveActiveWorkoutPointer(
    WorkoutDto workout, {
    String? label,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ptr = ActiveWorkoutPointer(
        workoutId: workout.id,
        startedAt: workout.startedAt,
        label: label,
      );
      await prefs.setString(kActiveWorkoutPrefsKey, jsonEncode(ptr.toJson()));
    } catch (e) {
      debugPrint('[active-workout] save failed: $e');
    }
  }

  /// Read the pointer (if any). Returns null when missing/malformed.
  static Future<ActiveWorkoutPointer?> readActiveWorkoutPointer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ActiveWorkoutPointer.tryParse(
          prefs.getString(kActiveWorkoutPrefsKey));
    } catch (e) {
      debugPrint('[active-workout] read failed: $e');
      return null;
    }
  }

  /// Clear the pointer. If [matchingId] is supplied, only clears when the
  /// stored pointer references the same workout (avoids stomping a newer
  /// session that may have started during the same app run).
  static Future<void> clearActiveWorkoutPointer({String? matchingId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (matchingId != null) {
        final cur = ActiveWorkoutPointer.tryParse(
            prefs.getString(kActiveWorkoutPrefsKey));
        if (cur != null && cur.workoutId != matchingId) return;
      }
      await prefs.remove(kActiveWorkoutPrefsKey);
    } catch (e) {
      debugPrint('[active-workout] clear failed: $e');
    }
  }

  /// GET /v1/me/workout-suggestion — AI-built suggestion from profile + exercise catalog.
  Future<WorkoutSuggestionDto> getWorkoutSuggestion(
      {bool refresh = false}) async {
    if (!refresh) {
      final cached = await AppDataCache.instance.loadWorkoutSuggestion();
      if (cached != null) {
        return WorkoutSuggestionDto.fromJson(cached);
      }
    }

    final uri = Uri.parse('$v1Base/me/workout-suggestion').replace(
      queryParameters: refresh ? const {'refresh': 'true'} : null,
    );
    final res = await http
        .get(
          uri,
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      final cached = await AppDataCache.instance.loadWorkoutSuggestion();
      if (cached != null) return WorkoutSuggestionDto.fromJson(cached);
      _throw(res);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final suggestion = data['suggestion'] as Map<String, dynamic>;
    await AppDataCache.instance.saveWorkoutSuggestion(suggestion);
    return WorkoutSuggestionDto.fromJson(suggestion);
  }

  /// GET /v1/exercises — optional [pattern] filters `movementPattern` (e.g. `squat`).
  Future<ExercisesResponse> getExercises({
    String? query,
    String? pattern,
    String? source,
    int limit = 50,
  }) async {
    final q = <String, String>{'limit': '$limit'};
    if (query != null && query.isNotEmpty) q['query'] = query;
    if (pattern != null && pattern.isNotEmpty) q['pattern'] = pattern;
    if (source != null && source.isNotEmpty) q['source'] = source;
    final res = await http
        .get(
          Uri.parse('$v1Base/exercises').replace(queryParameters: q),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
    return ExercisesResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Most recent completed WORK-set weight (kg) per exercise id, for pre-filling
  /// preset sets from the user's real history. Best-effort: returns {} on any
  /// failure so callers fall back to their static defaults.
  Future<Map<String, double>> getLastWorkingWeights(
      List<String> exerciseIds) async {
    if (exerciseIds.isEmpty) return {};
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/exercises/last-weights')
                .replace(queryParameters: {'ids': exerciseIds.join(',')}),
            headers: await _headers(),
          )
          .withTimeout();
      if (res.statusCode != 200) return {};
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'];
      if (data is! Map) return {};
      final out = <String, double>{};
      data.forEach((k, v) {
        final n = v is num ? v.toDouble() : double.tryParse('$v');
        if (n != null && n > 0) out['$k'] = n;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// GET /v1/exercises/:id/progression — the brief's §8.3 auto-progression: the
  /// suggested next working load for [exerciseId] from the user's WORK-set
  /// history (+ a "why" reason for explainability). Best-effort: null on any
  /// failure so the tracker just shows no hint.
  Future<ProgressionSuggestion?> getProgression(String exerciseId,
      {int reps = 8}) async {
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/exercises/$exerciseId/progression')
                .replace(queryParameters: {'reps': '$reps'}),
            headers: await _headers(),
          )
          .withTimeout();
      if (res.statusCode != 200) return null;
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'];
      if (data is! Map) return null;
      return ProgressionSuggestion.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<ExerciseDto> getExercise(String id) async {
    final res = await http
        .get(
          Uri.parse('$v1Base/exercises/$id'),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ExerciseDto.fromJson(data['exercise'] as Map<String, dynamic>);
  }

  /// POST /v1/exercises/custom — create a user's custom exercise. The endpoint
  /// contract follows CLAUDE.md's API conventions; adjust field names if the
  /// backend differs.
  Future<ExerciseDto> createCustomExercise({
    required String name,
    String? primaryMuscle,
    String? equipment,
  }) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/exercises/custom'),
          headers: await _headers(),
          body: jsonEncode({
            'name': name,
            if (primaryMuscle != null && primaryMuscle.isNotEmpty)
              'primaryMuscle': primaryMuscle,
            if (equipment != null && equipment.isNotEmpty)
              'equipment': equipment,
          }),
        )
        .withTimeout();
    if (res.statusCode != 201 && res.statusCode != 200) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final ex = data['exercise'] ?? data;
    return ExerciseDto.fromJson(ex as Map<String, dynamic>);
  }

  /// POST /v1/me/planned-workouts/generate-weekly
  Future<GenerateWeeklyPlanResult> generateWeeklyPlan(
      {bool force = false}) async {
    final tzOffset = DateTime.now().timeZoneOffset.inMinutes;
    final res = await http
        .post(
          Uri.parse('$v1Base/me/planned-workouts/generate-weekly'),
          headers: await _headers(),
          body: jsonEncode({'tzOffset': tzOffset, 'force': force}),
        )
        .withAiTimeout();
    if (res.statusCode != 200 && res.statusCode != 201) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final workouts = (data['workouts'] as List<dynamic>)
        .map((e) => PlannedWorkoutDto.fromJson(e as Map<String, dynamic>))
        .toList();
    return GenerateWeeklyPlanResult(
      weekStart: data['weekStart'] as String,
      generated: data['generated'] as bool? ?? false,
      workouts: workouts,
    );
  }

  /// PATCH /v1/me/planned-workouts/:id
  Future<void> patchPlannedWorkout(String id, String status) async {
    final res = await http
        .patch(
          Uri.parse('$v1Base/me/planned-workouts/$id'),
          headers: await _headers(),
          body: jsonEncode({'status': status}),
        )
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
  }

  /// DELETE /v1/me/planned-workouts/:id
  Future<void> deletePlannedWorkout(String id) async {
    final res = await http
        .delete(
          Uri.parse('$v1Base/me/planned-workouts/$id'),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200 && res.statusCode != 204) _throw(res);
  }

  /// GET /v1/ranks/leaderboard — leaderboard sezon curent.
  Future<SeasonLeaderboardResponse> getSeasonLeaderboard(
      {int limit = 50}) async {
    final res = await http
        .get(
          Uri.parse('$v1Base/ranks/leaderboard')
              .replace(queryParameters: {'limit': '$limit'}),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
    return SeasonLeaderboardResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// GET /v1/ranks/leaderboard — poziția ta în sezon (null dacă nu ești în top).
  Future<int?> getMySeasonLeaderboardRank({int limit = 100}) async {
    final userId = await _auth.getCurrentUserId();
    if (userId == null) return null;
    final res = await http
        .get(
          Uri.parse('$v1Base/ranks/leaderboard')
              .replace(queryParameters: {'limit': '$limit'}),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['leaderboard'] as List<dynamic>? ?? [];
    for (final row in list) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      if (m['userId'] == userId) return (m['rank'] as num?)?.toInt();
    }
    return null;
  }

  // NOTE: the old saveOutdoorSession (POST /v1/workouts/cardio) was removed —
  // that endpoint never existed server-side (silent 404). Outdoor sessions now
  // persist via ActivityService.saveActivity → POST /v1/activities, with
  // offline replay through PendingActivityQueue.

  /// GET /v1/ranks/me — all user ranks
  Future<List<ExerciseRankDto>> getMyRanks() async {
    // Wrapped so a network / parse failure logs to Crashlytics instead of
    // returning an empty list that the UI can't distinguish from "user
    // genuinely has no ranks yet". xp_complete_screen still falls back to
    // its empty hint when this returns [].
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/ranks/me'),
            headers: await _headers(),
          )
          .withTimeout();
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['ranks'] as List<dynamic>? ?? [];
      return list
          .map((e) => ExerciseRankDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      _logRankError(e, st);
      return [];
    }
  }

  void _logRankError(Object e, StackTrace st) {
    debugPrint('[WorkoutService.getMyRanks] $e');
  }

  /// GET /v1/ranks/exercises/:id/explain
  Future<Map<String, dynamic>> getRankExplain(String exerciseId) async {
    final res = await http
        .get(
          Uri.parse('$v1Base/ranks/exercises/$exerciseId/explain'),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// GET /v1/ranks/me/history — progression history for all exercises
  Future<List<ExerciseProgressionDto>> getMyProgressionHistory() async {
    final res = await http
        .get(
          Uri.parse('$v1Base/ranks/me/history'),
          headers: await _headers(),
        )
        .withTimeout();
    if (res.statusCode != 200) _throw(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final progressions = (data['progressions'] as List<dynamic>?) ?? [];
    return progressions
        .map((p) => ExerciseProgressionDto.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/me/workouts/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD
  ///
  /// **Backend dependency (QA P1.2):** endpoint not yet implemented; we map
  /// 404 → empty list so the calendar continues to work against the local
  /// sqflite cache. Auth errors throw [CalendarAuthException]; network /
  /// timeout / 5xx bubble as plain [Exception] so the screen can keep the
  /// cached UI without surfacing a snackbar.
  ///
  /// Accepts both `{ dates: [{ date }] }` and a bare `[{ date }]` envelope.
  Future<List<DateTime>> getWorkoutCalendar(
      {DateTime? from, DateTime? to}) async {
    String ymd(DateTime d) {
      final l = d.toLocal();
      return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
    }

    final qp = <String, String>{};
    if (from != null) qp['from'] = ymd(from);
    if (to != null) qp['to'] = ymd(to);

    final token = await _auth.getAccessToken();
    if (token == null) throw const CalendarAuthException();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$v1Base/me/workouts/calendar')
        .replace(queryParameters: qp.isEmpty ? null : qp);
    final res = await http
        .get(uri, headers: headers)
        .withTimeout(const Duration(seconds: 12));

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const CalendarAuthException('Unauthorized');
    }
    if (res.statusCode == 404) return const [];
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Calendar request failed (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    final List<dynamic> raw;
    if (decoded is Map<String, dynamic>) {
      raw = (decoded['dates'] as List<dynamic>?) ?? const [];
    } else if (decoded is List<dynamic>) {
      raw = decoded;
    } else {
      return const [];
    }

    final out = <DateTime>[];
    for (final e in raw) {
      String? s;
      if (e is String) {
        s = e;
      } else if (e is Map && e['date'] is String) {
        s = e['date'] as String;
      }
      if (s == null || s.isEmpty) continue;
      // Accept "YYYY-MM-DD" or full ISO; DateTime.tryParse handles both.
      final d = DateTime.tryParse(s);
      if (d != null) out.add(DateTime(d.year, d.month, d.day));
    }
    return out;
  }

  /// GET /v1/me/workouts/heatmap?year=YYYY
  ///
  /// Returns a `{ "YYYY-MM-DD": count }` map for the profile workout-density
  /// heatmap (QA P1.13). Defaults to the current year. Accepts two envelope
  /// shapes from the backend:
  ///   - `{ "days": [ { "date": "YYYY-MM-DD", "count": 3 }, ... ] }`
  ///   - `{ "2026-01-15": 3, "2026-01-16": 1, ... }`
  ///
  /// Errors:
  ///   - 404 → empty map (endpoint not yet shipped; heatmap renders empty).
  ///   - 401/403/5xx/timeout → throws [HeatmapRequestException] with statusCode
  ///     so the widget can render an inline "Couldn't load activity history".
  Future<Map<String, int>> getWorkoutHeatmap({int? year}) async {
    final y = year ?? DateTime.now().year;
    final token = await _auth.getAccessToken();
    if (token == null) {
      throw const HeatmapRequestException(401, 'Not signed in');
    }
    final uri = Uri.parse('$v1Base/me/workouts/heatmap')
        .replace(queryParameters: {'year': '$y'});
    final res = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    }).withTimeout(const Duration(seconds: 12));

    if (res.statusCode == 404) return const <String, int>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HeatmapRequestException(
        res.statusCode,
        'Heatmap request failed (${res.statusCode})',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on FormatException {
      return const <String, int>{};
    }
    if (decoded is! Map<String, dynamic>) return const <String, int>{};

    final out = <String, int>{};
    final daysList = decoded['days'];
    if (daysList is List) {
      // Shape 1: { days: [{date, count}, ...] }
      for (final e in daysList) {
        if (e is! Map) continue;
        final date = e['date'];
        final count = e['count'];
        if (date is! String || date.isEmpty) continue;
        final n = count is num ? count.toInt() : int.tryParse('$count') ?? 0;
        if (n > 0) out[date] = n;
      }
    } else {
      // Shape 2: flat { "YYYY-MM-DD": n } (skip non-date keys defensively).
      decoded.forEach((k, v) {
        if (k.length < 10) return;
        final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
        if (n > 0) out[k] = n;
      });
    }
    return out;
  }

  void _throw(http.Response res) {
    String? message;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      final m = body?['message'];
      if (m != null) message = m.toString();
    } on FormatException {
      // fallthrough
    }
    throw WorkoutApiException(
      statusCode: res.statusCode,
      message: message ?? 'Server error (${res.statusCode})',
    );
  }

  /// True when the response is the anti-cheat `WEIGHT_JUMP_REQUIRES_NOTE` error.
  bool _isWeightJump(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      return body?['error'] == 'WEIGHT_JUMP_REQUIRES_NOTE';
    } on FormatException {
      return false;
    }
  }

  /// Best-effort `message` field from a JSON error body (null if absent/unparsable).
  String? _messageOf(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      final m = body?['message'];
      return m?.toString();
    } on FormatException {
      return null;
    }
  }
}

/// Thrown by [WorkoutService] for any non-2xx response. The status code lets
/// callers distinguish drop-on-retry (4xx) from network/server transient (5xx).
class WorkoutApiException implements Exception {
  WorkoutApiException({required this.statusCode, required this.message});
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

// ─── JSON coercion helpers ───────────────────────────────────────────────────
// Prisma Decimal/int fields arrive as Strings over JSON; these small variants
// share the parsing logic while preserving each call site's exact null/fallback/
// throw semantics. Do NOT collapse the nullable/strict/fallback flavors into one
// — that would change behavior.

/// num → int; String/other → `int.tryParse`; null → null. Never throws.
int? _asNullableInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// num → double; String/other → `double.tryParse`; null → null. Never throws.
double? _asNullableDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// num → int; String/other → `int.parse` (THROWS on bad input).
int _asIntStrict(dynamic v) => v is num ? v.toInt() : int.parse(v.toString());

/// num → double; String/other → `double.parse` (THROWS on bad input).
double _asDoubleStrict(dynamic v) =>
    v is num ? v.toDouble() : double.parse(v.toString());

/// num → int; String → `int.tryParse` else [fallback]; other/null → [fallback].
int _asIntOr(dynamic v, int fallback) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

/// num → double; String/other → `double.tryParse` else [fallback]; null → [fallback].
double _asDoubleOr(dynamic v, double fallback) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

/// Prisma → JSON e camelCase; acceptă și snake_case dacă răspunsul e transformat.
String? _pickStr(Map<String, dynamic> j, String camel, [String? snake]) {
  final x = snake != null ? (j[camel] ?? j[snake]) : j[camel];
  if (x == null) return null;
  return x.toString();
}

// ─── DTOs ───────────────────────────────────────────────────────────────────

class CompleteWorkoutResult {
  const CompleteWorkoutResult({
    required this.workout,
    required this.xpGain,
    this.ageMultiplier = 1.0,
    this.gameXp,
    this.xpBreakdown = const [],
  });

  final WorkoutDto workout;
  final int xpGain;

  /// Age-based XP bonus applied by the server (e.g. 1.22 for a 55-year-old).
  /// 1.0 means no bonus or no birth year on profile. Surface this on the XP
  /// screen so older lifters see why their XP is higher than the same lift
  /// from someone 25.
  final double ageMultiplier;
  final GameXpSnapshot? gameXp;
  final List<XpBreakdownLine> xpBreakdown;
}

/// Auto-progression suggestion (brief §8.3) from
/// GET /v1/exercises/:id/progression.
class ProgressionSuggestion {
  ProgressionSuggestion({
    this.suggestedWeightKg,
    required this.suggestedReps,
    required this.source,
    required this.reason,
  });

  /// Suggested working weight (kg); null for bodyweight / no-history lifts.
  final double? suggestedWeightKg;
  final int suggestedReps;

  /// 'progression' | 'hold' | 'deload' | 'no_history' — drives the chip color/icon.
  final String source;

  /// Human "why this load?" explanation.
  final String reason;

  static ProgressionSuggestion fromJson(Map<String, dynamic> j) {
    final w = j['suggestedWeightKg'];
    return ProgressionSuggestion(
      suggestedWeightKg:
          w == null ? null : (w is num ? w.toDouble() : double.tryParse('$w')),
      suggestedReps: (j['suggestedReps'] as num?)?.toInt() ?? 8,
      source: j['source'] as String? ?? 'progression',
      reason: j['reason'] as String? ?? '',
    );
  }
}

class WorkoutDto {
  WorkoutDto({
    required this.id,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.notes,
    this.exercises = const [],
  });
  final String id;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Program/planned sessions carry their real name here as
  /// "From plan: <title>" (planned-workout-converter) — used to show a
  /// meaningful title instead of the generated "<Muscle> Day".
  final String? notes;
  final List<WorkoutExerciseDto> exercises;

  /// The planned/program session title when present, else null.
  String? get planTitle {
    final n = notes?.trim();
    if (n == null || !n.startsWith('From plan: ')) return null;
    final t = n.substring('From plan: '.length).trim();
    return t.isEmpty ? null : t;
  }

  /// Best human-facing session title carried by the backend notes field.
  String? get sessionTitle {
    final n = notes?.trim();
    if (n == null || n.isEmpty) return null;
    const planPrefix = 'From plan: ';
    if (n.startsWith(planPrefix)) {
      final t = n.substring(planPrefix.length).trim();
      return t.isEmpty ? null : t;
    }
    const sessionPrefix = 'Session: ';
    if (n.startsWith(sessionPrefix)) {
      final t = n.substring(sessionPrefix.length).trim();
      return t.isEmpty ? null : t;
    }
    if (!n.contains('\n') && n.length <= 80) return n;
    return null;
  }

  static WorkoutDto fromJson(Map<String, dynamic> j) {
    final exercises = (j['exercises'] as List<dynamic>?)
            ?.map((e) => WorkoutExerciseDto.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return WorkoutDto(
      id: j['id'] as String,
      status: j['status'] as String? ?? 'draft',
      startedAt: DateTime.parse(j['startedAt'] as String),
      endedAt:
          j['endedAt'] != null ? DateTime.parse(j['endedAt'] as String) : null,
      notes: j['notes'] as String?,
      exercises: exercises,
    );
  }
}

class WorkoutExerciseDto {
  WorkoutExerciseDto({
    required this.id,
    required this.exerciseId,
    required this.position,
    required this.exercise,
    this.sets = const [],
    this.repRangeHint,
    this.restSecondsDefault,
  });
  final String id;
  final String exerciseId;
  final int position;
  final ExerciseDto exercise;
  final List<WorkoutSetDto> sets;
  final String? repRangeHint;
  final int? restSecondsDefault;

  static WorkoutExerciseDto fromJson(Map<String, dynamic> j) {
    final sets = (j['sets'] as List<dynamic>?)
            ?.map((s) => WorkoutSetDto.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [];
    return WorkoutExerciseDto(
      id: j['id'] as String,
      exerciseId: j['exerciseId'] as String,
      position: j['position'] is num
          ? (j['position'] as num).toInt()
          : int.parse(j['position'].toString()),
      exercise: ExerciseDto.fromJson(j['exercise'] as Map<String, dynamic>),
      sets: sets,
      repRangeHint: j['repRangeHint'] as String?,
      restSecondsDefault: _asNullableInt(j['restSecondsDefault']),
    );
  }
}

class WorkoutSetDto {
  WorkoutSetDto({
    required this.id,
    required this.setIndex,
    required this.weightKg,
    required this.reps,
    this.rpe,
    required this.tag,
    this.isCompleted = true,
  });
  final String id;
  final int setIndex;
  final double weightKg;
  final int reps;
  final double? rpe;
  final String tag;
  final bool isCompleted;

  static WorkoutSetDto fromJson(Map<String, dynamic> j) {
    // Prisma Decimal fields come back as String over JSON — parse safely.
    return WorkoutSetDto(
      id: j['id'] as String,
      setIndex: _asIntStrict(j['setIndex']),
      weightKg: _asDoubleStrict(j['weightKg']),
      reps: _asIntStrict(j['reps']),
      rpe: j['rpe'] != null ? _asDoubleStrict(j['rpe']) : null,
      tag: j['tag'] as String? ?? 'WORK',
      isCompleted: j['isCompleted'] as bool? ?? true,
    );
  }
}

class ExerciseDto {
  ExerciseDto({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.primaryMuscle,
    this.secondaryMuscles = const [],
    this.equipment,
    this.category,
    this.movementPattern,
    this.rankModel,
    this.secondaryPatterns = const [],
    this.fatigueScore,
    this.goalTags = const [],
    this.contraindications = const [],
    this.beginnerSuitable = true,
    this.instructions = const [],
    this.sourceProvider,
    this.media = const [],
  });
  final String id;
  final String name;
  final String? slug;
  final String? description;
  final String? primaryMuscle;
  final List<String> secondaryMuscles;
  final String? equipment;
  final String? category;
  final String? movementPattern;

  /// WEIGHTED | BW_REPS | TIME — from API / Prisma.
  final String? rankModel;
  final List<String> secondaryPatterns;
  final int? fatigueScore;
  final List<String> goalTags;
  final List<String> contraindications;
  final bool beginnerSuitable;
  final List<String> instructions;
  final String? sourceProvider;
  final List<ExerciseMediaDto> media;

  static List<String> _stringList(dynamic v) {
    if (v is! List) return const [];
    return v.map((e) => e.toString()).toList();
  }

  static ExerciseDto fromJson(Map<String, dynamic> j) {
    final beginnerRaw = j['beginnerSuitable'] ?? j['beginner_suitable'];
    final beginner = beginnerRaw is bool
        ? beginnerRaw
        : beginnerRaw == null
            ? true
            : beginnerRaw.toString() == 'true';

    return ExerciseDto(
      id: j['id'] as String,
      name: j['name'] as String,
      slug: _pickStr(j, 'slug'),
      description: _pickStr(j, 'description'),
      primaryMuscle: _pickStr(j, 'primaryMuscle', 'primary_muscle'),
      secondaryMuscles:
          _stringList(j['secondaryMuscles'] ?? j['secondary_muscles']),
      equipment: _pickStr(j, 'equipment'),
      category: _pickStr(j, 'category'),
      movementPattern: _pickStr(j, 'movementPattern', 'movement_pattern'),
      rankModel: _pickStr(j, 'rankModel', 'rank_model'),
      secondaryPatterns:
          _stringList(j['secondaryPatterns'] ?? j['secondary_patterns']),
      fatigueScore: _asNullableInt(j['fatigueScore'] ?? j['fatigue_score']),
      goalTags: _stringList(j['goalTags'] ?? j['goal_tags']),
      contraindications: _stringList(j['contraindications']),
      beginnerSuitable: beginner,
      instructions: _stringList(j['instructions']),
      sourceProvider: _pickStr(j, 'sourceProvider', 'source_provider'),
      media: (j['media'] as List<dynamic>?)
              ?.map((e) => ExerciseMediaDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class ExerciseMediaDto {
  const ExerciseMediaDto({
    required this.id,
    required this.kind,
    required this.url,
    this.thumbnailUrl,
    this.license,
    this.attribution,
    this.sourcePageUrl,
  });

  final String id;
  final String kind;
  final String url;
  final String? thumbnailUrl;
  final String? license;
  final String? attribution;
  final String? sourcePageUrl;

  bool get isVideo =>
      kind == 'video' ||
      url.toLowerCase().endsWith('.mp4') ||
      url.toLowerCase().endsWith('.webm');

  String get previewUrl =>
      thumbnailUrl?.isNotEmpty == true ? thumbnailUrl! : url;

  static ExerciseMediaDto fromJson(Map<String, dynamic> j) {
    return ExerciseMediaDto(
      id: j['id'] as String,
      kind: _pickStr(j, 'kind') ?? 'image',
      url: _pickStr(j, 'url') ?? '',
      thumbnailUrl: _pickStr(j, 'thumbnailUrl', 'thumbnail_url'),
      license: _pickStr(j, 'license'),
      attribution: _pickStr(j, 'attribution'),
      sourcePageUrl: _pickStr(j, 'sourcePageUrl', 'source_page_url'),
    );
  }
}

class WorkoutsResponse {
  WorkoutsResponse({required this.data, required this.meta});
  final List<WorkoutDto> data;
  final WorkoutsMeta meta;

  static WorkoutsResponse fromJson(Map<String, dynamic> j) {
    final data = (j['data'] as List<dynamic>)
        .map((e) => WorkoutDto.fromJson(e as Map<String, dynamic>))
        .toList();
    return WorkoutsResponse(
      data: data,
      meta: WorkoutsMeta.fromJson(j['meta'] as Map<String, dynamic>),
    );
  }
}

class WorkoutsMeta {
  WorkoutsMeta(
      {required this.page,
      required this.limit,
      required this.total,
      required this.totalPages});
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  static WorkoutsMeta fromJson(Map<String, dynamic> j) {
    return WorkoutsMeta(
      page: _asIntStrict(j['page']),
      limit: _asIntStrict(j['limit']),
      total: _asIntStrict(j['total']),
      totalPages: _asIntStrict(j['totalPages']),
    );
  }
}

class ExercisesResponse {
  ExercisesResponse({required this.data});
  final List<ExerciseDto> data;

  static ExercisesResponse fromJson(Map<String, dynamic> j) {
    final data = (j['data'] as List<dynamic>)
        .map((e) => ExerciseDto.fromJson(e as Map<String, dynamic>))
        .toList();
    return ExercisesResponse(data: data);
  }
}

class SuggestedExerciseDto {
  SuggestedExerciseDto({
    required this.exerciseId,
    required this.name,
    required this.movementPattern,
    this.primaryMuscle,
    this.equipment,
    required this.sets,
    required this.repRange,
    required this.restSeconds,
    required this.suggestedWeightKg,
    required this.weightSource,
    this.whyThisExercise,
  });
  final String exerciseId;
  final String name;
  final String movementPattern;
  final String? primaryMuscle;
  final String? equipment;
  final int sets;
  final String repRange;
  final int restSeconds;

  /// AI-calculated starting weight; 0 = bodyweight / no load.
  final double suggestedWeightKg;

  /// 'history' | 'heuristic' | 'bodyweight' — used for UI hints.
  final String weightSource;

  /// One-sentence rationale for why THIS exercise fits the user's stated goal.
  /// Null when the AI omitted it (older cached sessions) or when no goal was set.
  final String? whyThisExercise;

  static SuggestedExerciseDto fromJson(Map<String, dynamic> j) {
    final whyRaw = (j['whyThisExercise'] as String?)?.trim();
    return SuggestedExerciseDto(
      exerciseId: j['exerciseId'] as String,
      name: j['name'] as String,
      movementPattern: j['movementPattern'] as String? ?? 'skill_stability',
      primaryMuscle: j['primaryMuscle'] as String?,
      equipment: j['equipment'] as String?,
      sets: _asIntStrict(j['sets']),
      repRange: j['repRange'] as String? ?? '',
      restSeconds: _asIntStrict(j['restSeconds']),
      suggestedWeightKg: _asDoubleOr(j['suggestedWeightKg'], 0.0),
      weightSource: j['weightSource'] as String? ?? 'heuristic',
      whyThisExercise: (whyRaw != null && whyRaw.isNotEmpty) ? whyRaw : null,
    );
  }
}

class WorkoutSuggestionDto {
  WorkoutSuggestionDto({
    required this.blueprintId,
    required this.title,
    required this.description,
    this.primaryGoal,
    required this.exercises,
    required this.warnings,
  });
  final String blueprintId;
  final String title;
  final String description;
  final String? primaryGoal;
  final List<SuggestedExerciseDto> exercises;
  final List<String> warnings;

  static WorkoutSuggestionDto fromJson(Map<String, dynamic> j) {
    final ex = (j['exercises'] as List<dynamic>?)
            ?.map(
                (e) => SuggestedExerciseDto.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final w =
        (j['warnings'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            const [];
    return WorkoutSuggestionDto(
      blueprintId: j['blueprintId'] as String? ?? '',
      title: j['title'] as String? ?? 'Workout',
      description: j['description'] as String? ?? '',
      primaryGoal: j['primaryGoal'] as String?,
      exercises: ex,
      warnings: w,
    );
  }
}

// ─── Planned Workouts ────────────────────────────────────────────────────────

class PlannedWorkoutDto {
  PlannedWorkoutDto({
    required this.id,
    required this.day,
    required this.weekStart,
    required this.title,
    required this.kind,
    required this.status,
    this.exercises = const [],
    this.notes,
  });

  final String id;

  /// ISO date string "YYYY-MM-DD"
  final String day;
  final String weekStart;
  final String title;
  final String kind;

  /// "pending" | "completed"
  final String status;

  /// AI plan for the day. Each item has name, sets, reps, restSeconds and
  /// (optionally) a resolved exerciseId pointing at a real Exercise row.
  final List<PlannedExerciseDto> exercises;

  /// Free-text focus / coaching note for the day.
  final String? notes;

  PlannedWorkoutDto copyWith({String? status}) => PlannedWorkoutDto(
        id: id,
        day: day,
        weekStart: weekStart,
        title: title,
        kind: kind,
        status: status ?? this.status,
        exercises: exercises,
        notes: notes,
      );

  static PlannedWorkoutDto fromJson(Map<String, dynamic> j) {
    final exRaw = j['exercisesJson'] ?? j['exercises_json'] ?? j['exercises'];
    final exercises = exRaw is List
        ? exRaw
            .whereType<Map>()
            .map((m) =>
                PlannedExerciseDto.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : const <PlannedExerciseDto>[];
    return PlannedWorkoutDto(
      id: j['id'] as String,
      day: j['day'] as String,
      weekStart: j['weekStart'] as String,
      title: j['title'] as String? ?? 'Session',
      kind: j['kind'] as String? ?? 'strength',
      status: j['status'] as String? ?? 'pending',
      exercises: exercises,
      notes: j['notes'] as String?,
    );
  }
}

class PlannedExerciseDto {
  PlannedExerciseDto({
    required this.name,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    this.notes,
    this.exerciseId,
    this.suggestedWeightKg,
    this.loadSource,
    this.loadReason,
    this.whyThisExercise,
  });

  final String name;
  final int sets;
  final int reps;
  final int restSeconds;
  final String? notes;

  /// Set when name matched an existing Exercise row server-side; null when the
  /// AI invented a name and the resolver gave up. UI should still show `name`.
  final String? exerciseId;

  /// Deterministic progressive-overload pick (null for bodyweight / no history).
  final double? suggestedWeightKg;

  /// 'progression' | 'hold' | 'no_history' — drives "why this load?" tooltip.
  final String? loadSource;

  /// One-line human-readable reason for the chosen load (explainability).
  final String? loadReason;

  /// Two short sentences from the AI: (1) what the exercise builds, (2) why
  /// it's the right pick for the user's stated goal. Null on older plans
  /// generated before the prompt change.
  final String? whyThisExercise;

  static PlannedExerciseDto fromJson(Map<String, dynamic> j) {
    final whyRaw = (j['whyThisExercise'] as String?)?.trim();
    return PlannedExerciseDto(
      name: j['name']?.toString() ?? 'Exercise',
      sets: _asIntOr(j['sets'], 3),
      reps: _asIntOr(j['reps'], 8),
      restSeconds: _asIntOr(j['restSeconds'] ?? j['rest_seconds'], 90),
      notes: j['notes'] as String?,
      exerciseId: j['exerciseId'] as String? ?? j['exercise_id'] as String?,
      suggestedWeightKg:
          _asNullableDouble(j['suggestedWeightKg'] ?? j['suggested_weight_kg']),
      loadSource: j['loadSource'] as String? ?? j['load_source'] as String?,
      loadReason: j['loadReason'] as String? ?? j['load_reason'] as String?,
      whyThisExercise: (whyRaw != null && whyRaw.isNotEmpty) ? whyRaw : null,
    );
  }
}

class GenerateWeeklyPlanResult {
  GenerateWeeklyPlanResult({
    required this.weekStart,
    required this.generated,
    required this.workouts,
  });

  final String weekStart;
  final bool generated;
  final List<PlannedWorkoutDto> workouts;
}

class ExerciseRankDto {
  ExerciseRankDto({
    required this.exerciseId,
    required this.exerciseName,
    required this.lpTotal,
    required this.tier,
    required this.bestE1rmKg,
    required this.strengthRatio,
  });
  final String exerciseId;
  final String exerciseName;
  final int lpTotal;
  final String tier;
  final double bestE1rmKg;
  final double strengthRatio;

  int get lpInTier => lpTotal % 100;

  static String _lpToTier(int lp) {
    const tiers = [
      'Iron',
      'Bronze',
      'Silver',
      'Gold',
      'Platinum',
      'Diamond',
      'Olympian'
    ];
    return tiers[(lp ~/ 100).clamp(0, tiers.length - 1)];
  }

  static ExerciseRankDto fromJson(Map<String, dynamic> j) {
    final lp = (j['lpTotal'] as num?)?.toInt() ?? 0;
    return ExerciseRankDto(
      exerciseId: j['exerciseId'] as String? ?? '',
      exerciseName:
          (j['exercise'] as Map<String, dynamic>?)?['name'] as String? ??
              j['exerciseName'] as String? ??
              '',
      lpTotal: lp,
      tier: j['tier'] as String? ?? _lpToTier(lp),
      bestE1rmKg: _asDoubleOr(j['bestE1rmKg'] ?? 0, 0),
      strengthRatio: _asDoubleOr(j['strengthRatio'] ?? 0, 0),
    );
  }
}

/// GET /v1/ranks/me/history — progression data point
class ProgressionPointDto {
  ProgressionPointDto({
    required this.date,
    required this.e1rmKg,
    required this.lp,
    required this.tier,
    required this.weightKg,
    required this.reps,
  });
  final String date;
  final double e1rmKg;
  final int lp;
  final String tier;
  final double weightKg;
  final int reps;

  static ProgressionPointDto fromJson(Map<String, dynamic> j) {
    return ProgressionPointDto(
      date: j['date'] as String? ?? '',
      e1rmKg: _asDoubleOr(j['e1rmKg'] ?? 0, 0),
      lp: (j['lp'] as num?)?.toInt() ?? 0,
      tier: j['tier'] as String? ?? 'Iron',
      weightKg: _asDoubleOr(j['weightKg'] ?? 0, 0),
      reps: (j['reps'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Exercise progression over time
class ExerciseProgressionDto {
  ExerciseProgressionDto({
    required this.exerciseId,
    required this.exerciseName,
    required this.currentLP,
    required this.currentTier,
    required this.bestE1rmKg,
    required this.dataPoints,
  });
  final String exerciseId;
  final String exerciseName;
  final int currentLP;
  final String currentTier;
  final double bestE1rmKg;
  final List<ProgressionPointDto> dataPoints;

  int get lpInTier => currentLP % 100;

  static ExerciseProgressionDto fromJson(Map<String, dynamic> j) {
    final points = (j['dataPoints'] as List<dynamic>?)
            ?.map(
                (p) => ProgressionPointDto.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];
    return ExerciseProgressionDto(
      exerciseId: j['exerciseId'] as String? ?? '',
      exerciseName: j['exerciseName'] as String? ?? '',
      currentLP: (j['currentLP'] as num?)?.toInt() ?? 0,
      currentTier: j['currentTier'] as String? ?? 'Iron',
      bestE1rmKg: _asDoubleOr(j['bestE1rmKg'] ?? 0, 0),
      dataPoints: points,
    );
  }
}

class SeasonLeaderboardEntry {
  const SeasonLeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.lpSeason,
  });

  final int rank;
  final String userId;
  final String username;
  final String displayName;
  final int lpSeason;

  String get label => displayName.isNotEmpty ? displayName : username;

  static SeasonLeaderboardEntry fromJson(Map<String, dynamic> j) =>
      SeasonLeaderboardEntry(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        userId: j['userId'] as String? ?? '',
        username: j['username'] as String? ?? 'Anonymous',
        displayName: j['displayName'] as String? ?? '',
        lpSeason: (j['lpSeason'] as num?)?.toInt() ?? 0,
      );
}

class SeasonLeaderboardResponse {
  const SeasonLeaderboardResponse({this.seasonName, required this.entries});

  final String? seasonName;
  final List<SeasonLeaderboardEntry> entries;

  static SeasonLeaderboardResponse fromJson(Map<String, dynamic> j) {
    final season = j['season'];
    String? seasonName;
    if (season is Map<String, dynamic>) {
      seasonName = season['name'] as String?;
    }
    final list = j['leaderboard'] as List<dynamic>? ?? [];
    return SeasonLeaderboardResponse(
      seasonName: seasonName,
      entries: list
          .whereType<Map>()
          .map((e) =>
              SeasonLeaderboardEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
