import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '_crash_reporter.dart';
import 'auth_service.dart';
import 'workout_service.dart';

/// The kind of "bootstrap" mutation a [PendingBootstrapEntry] replays on
/// reconnect. Bootstrap ops CREATE the skeleton a set needs (the workout row and
/// its workout_exercise rows). They MUST flush before the [OfflineSetQueue]'s
/// sets — a set POSTed against a not-yet-created exercise would 404 and be
/// dropped as an un-retryable 4xx (silent data loss).
///
///  * [createWorkout] — upsert a draft workout on its client PK ([workoutId]).
///  * [addExercise]   — upsert a workout_exercise on its client PK ([weId]).
///
/// Both replays are idempotent: the backend upserts on the supplied id, so
/// re-sending after a lost response returns the existing row instead of
/// duplicating it.
enum BootstrapOp { createWorkout, addExercise }

BootstrapOp _parseOp(dynamic raw) {
  switch (raw) {
    case 'addExercise':
      return BootstrapOp.addExercise;
    case 'createWorkout':
    default:
      return BootstrapOp.createWorkout;
  }
}

String _opToJson(BootstrapOp op) => switch (op) {
      BootstrapOp.createWorkout => 'createWorkout',
      BootstrapOp.addExercise => 'addExercise',
    };

/// A pending workout-create or exercise-create captured while offline (or when
/// the request failed) and replayed on reconnect.
///
/// For [BootstrapOp.createWorkout] the payload is [workoutId] (the client PK)
/// plus an optional [label]. For [BootstrapOp.addExercise] the payload is
/// [workoutId] (the parent), [exerciseId] (which catalog exercise), [weId] (the
/// client PK of the new workout_exercise) and an optional [position].
class PendingBootstrapEntry {
  const PendingBootstrapEntry({
    required this.op,
    required this.workoutId,
    this.label,
    this.exerciseId,
    this.weId,
    this.position,
    this.queuedAt,
    this.retryCount = 0,
    this.nextRetryAt,
  });

  /// CREATE-WORKOUT path. [workoutId] is the client-minted UUID used as the
  /// workout's PK; the same id is passed as `clientId` on replay so the local id
  /// equals the server id (no id remapping anywhere).
  factory PendingBootstrapEntry.createWorkout({
    required String workoutId,
    String? label,
    DateTime? queuedAt,
  }) =>
      PendingBootstrapEntry(
        op: BootstrapOp.createWorkout,
        workoutId: workoutId,
        label: label,
        queuedAt: queuedAt,
      );

  /// ADD-EXERCISE path. [weId] is the client-minted UUID used as the
  /// workout_exercise's PK — the SAME id every queued set targets.
  factory PendingBootstrapEntry.addExercise({
    required String workoutId,
    required String exerciseId,
    required String weId,
    int? position,
    DateTime? queuedAt,
  }) =>
      PendingBootstrapEntry(
        op: BootstrapOp.addExercise,
        workoutId: workoutId,
        exerciseId: exerciseId,
        weId: weId,
        position: position,
        queuedAt: queuedAt,
      );

  final BootstrapOp op;
  final String workoutId;

  /// createWorkout only — resume label; harmless if null.
  final String? label;

  /// addExercise only — which catalog exercise to attach.
  final String? exerciseId;

  /// addExercise only — the client PK of the new workout_exercise row.
  final String? weId;

  /// addExercise only — desired ordering; null lets the server auto-assign.
  final int? position;

  final DateTime? queuedAt;

  /// How many transient (5xx/network/auth-lapse) failures this entry has hit,
  /// and the earliest instant to retry — exponential backoff so a reconnect
  /// during an outage doesn't hammer a recovering backend. Mirrors
  /// [OfflineSetQueue]'s policy exactly.
  final int retryCount;
  final DateTime? nextRetryAt;

  PendingBootstrapEntry _afterTransientFailure(DateTime now) {
    final next = retryCount + 1;
    final delaySec = (1 << (next.clamp(0, 11))).clamp(2, 1800);
    return PendingBootstrapEntry(
      op: op,
      workoutId: workoutId,
      label: label,
      exerciseId: exerciseId,
      weId: weId,
      position: position,
      queuedAt: queuedAt,
      retryCount: next,
      nextRetryAt: now.add(Duration(seconds: delaySec)),
    );
  }

  Map<String, dynamic> toJson() => {
        'op': _opToJson(op),
        'workoutId': workoutId,
        if (label != null) 'label': label,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (weId != null) 'weId': weId,
        if (position != null) 'position': position,
        'queuedAt': (queuedAt ?? DateTime.now()).toIso8601String(),
        if (retryCount > 0) 'retryCount': retryCount,
        if (nextRetryAt != null) 'nextRetryAt': nextRetryAt!.toIso8601String(),
      };

  static PendingBootstrapEntry? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final workoutId = m['workoutId'] as String?;
    if (workoutId == null || workoutId.isEmpty) return null;
    final op = _parseOp(m['op']);
    final exerciseId = m['exerciseId'] as String?;
    final weId = m['weId'] as String?;
    // An addExercise with no target exercise or no client PK can never be
    // replayed (nothing to create / nothing for a set to point at) — drop it so
    // it can't loop forever.
    if (op == BootstrapOp.addExercise &&
        ((exerciseId == null || exerciseId.isEmpty) ||
            (weId == null || weId.isEmpty))) {
      return null;
    }
    return PendingBootstrapEntry(
      op: op,
      workoutId: workoutId,
      label: m['label'] as String?,
      exerciseId: exerciseId,
      weId: weId,
      position: (m['position'] as num?)?.toInt(),
      queuedAt:
          m['queuedAt'] != null ? DateTime.tryParse(m['queuedAt'] as String) : null,
      retryCount: (m['retryCount'] as num?)?.toInt() ?? 0,
      nextRetryAt: m['nextRetryAt'] != null
          ? DateTime.tryParse(m['nextRetryAt'] as String)
          : null,
    );
  }
}

/// Per-user SharedPreferences queue of pending workout-creates and
/// exercise-creates, mirroring [OfflineSetQueue]'s conventions (user-scoped key
/// via [AuthService.getStoredUserId], serialized read-modify-write lock, TTL,
/// cap, versioned JSON envelope).
///
/// [flush] replays IN ORDER — all createWorkout ops first, then addExercise ops
/// — so a workout always exists before its exercises, and an exercise before
/// any of its sets (the coordinator drains this queue before the set queue).
class OfflineBootstrapQueue {
  OfflineBootstrapQueue({AuthService? auth, WorkoutService? workouts})
      : _auth = auth ?? AuthService(),
        _workouts = workouts ?? WorkoutService();

  final AuthService _auth;
  final WorkoutService _workouts;

  static const _keyPrefix = 'zvelt_offline_bootstrap_queue_v1';
  static const int currentSchemaVersion = 1;

  /// Hard cap — a permanently-failing op must not grow the queue without bound.
  /// Oldest entries are dropped first (and reported).
  static const int maxEntries = 500;

  /// Entries older than this are condensed out on load/save (reported, never
  /// silent) — a create stuck failing for two weeks is tied to a workout the
  /// user has moved on from.
  static const Duration entryTtl = Duration(days: 14);

  Future<void> _lock = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Storage key scoped to the current user via the LOCAL JWT decode
  /// ([getStoredUserId]) — never a token-refreshing network call — so an offline
  /// enqueue and a later online flush resolve to the same bucket.
  Future<String> _key() async {
    final id = await _auth.getStoredUserId();
    return '${_keyPrefix}_${id ?? 'anon'}';
  }

  static const String _anonKey = '${_keyPrefix}_anon';

  Future<List<PendingBootstrapEntry>> _loadAllForKey(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return [];
    List<PendingBootstrapEntry> entries;
    try {
      entries = _decodeEnvelope(raw);
    } catch (_) {
      return [];
    }
    return _prune(entries, DateTime.now());
  }

  static List<PendingBootstrapEntry> _decodeEnvelope(String raw) {
    final decoded = jsonDecode(raw);
    final list = _migrateRaw(decoded);
    return list
        .map(PendingBootstrapEntry.fromJson)
        .whereType<PendingBootstrapEntry>()
        .toList();
  }

  /// Accepts a bare array (legacy) or the `{ schemaVersion, entries }` envelope,
  /// so a format change migrates queued ops forward instead of dropping them.
  static List<dynamic> _migrateRaw(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final entries = decoded['entries'];
      return entries is List ? entries : const [];
    }
    return const [];
  }

  static List<PendingBootstrapEntry> _prune(
    List<PendingBootstrapEntry> entries,
    DateTime now,
  ) {
    if (entries.isEmpty) return entries;
    final cutoff = now.subtract(entryTtl);
    final kept = <PendingBootstrapEntry>[];
    for (final e in entries) {
      final queuedAt = e.queuedAt;
      if (queuedAt != null && queuedAt.isBefore(cutoff)) {
        reportErrorNoStack(
          'offline bootstrap ${_opToJson(e.op)} dropped (ttl ${entryTtl.inDays}d): '
          'workout=${e.workoutId} we=${e.weId}',
          reason: 'offline-bootstrap:drop-ttl',
        );
        continue;
      }
      kept.add(e);
    }
    if (kept.length > maxEntries) {
      final overflow = kept.length - maxEntries;
      for (var i = 0; i < overflow; i++) {
        final e = kept[i];
        reportErrorNoStack(
          'offline bootstrap ${_opToJson(e.op)} dropped (cap $maxEntries exceeded): '
          'workout=${e.workoutId} we=${e.weId}',
          reason: 'offline-bootstrap:drop-cap',
        );
      }
      return kept.sublist(overflow);
    }
    return kept;
  }

  Future<List<PendingBootstrapEntry>> loadAll() async =>
      _loadAllForKey(await _key());

  Future<int> pendingCount() async => (await loadAll()).length;

  /// True when a createWorkout op for [workoutId] is still queued — the tracker
  /// uses this to synthesize an offline draft when [WorkoutService.getWorkout]
  /// fails (the workout doesn't exist server-side yet).
  Future<bool> hasPendingWorkout(String workoutId) async {
    for (final e in await loadAll()) {
      if (e.op == BootstrapOp.createWorkout && e.workoutId == workoutId) {
        return true;
      }
    }
    return false;
  }

  /// The queued addExercise ops for [workoutId], in enqueue order — lets a
  /// cold-reloaded tracker rebuild the exercise rows a user added offline.
  Future<List<PendingBootstrapEntry>> pendingExercisesFor(String workoutId) async {
    return [
      for (final e in await loadAll())
        if (e.op == BootstrapOp.addExercise && e.workoutId == workoutId) e,
    ];
  }

  Future<void> enqueueWorkout({required String workoutId, String? label}) {
    return _enqueue(
      PendingBootstrapEntry.createWorkout(workoutId: workoutId, label: label),
    );
  }

  Future<void> enqueueExercise({
    required String workoutId,
    required String exerciseId,
    required String weId,
    int? position,
  }) {
    return _enqueue(
      PendingBootstrapEntry.addExercise(
        workoutId: workoutId,
        exerciseId: exerciseId,
        weId: weId,
        position: position,
      ),
    );
  }

  Future<void> _enqueue(PendingBootstrapEntry entry) {
    return _synchronized(() async {
      final key = await _key();
      final all = await _loadAllForKey(key);
      all.add(entry);
      await _saveForKey(key, _prune(all, DateTime.now()));
    });
  }

  Future<void> _saveForKey(String key, List<PendingBootstrapEntry> entries) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      key,
      jsonEncode({
        'schemaVersion': currentSchemaVersion,
        'entries': entries.map((e) => e.toJson()).toList(),
      }),
    );
  }

  /// Replay all pending bootstrap ops. createWorkout ops flush FIRST, then
  /// addExercise ops, so a workout always exists before its exercises. An
  /// addExercise whose parent createWorkout is still pending (or just
  /// failed/deferred) is HELD BACK — sending it would 404. Its parent being
  /// permanently 4xx-dropped orphans it (dropped, not looped).
  ///
  /// Failure policy mirrors [OfflineSetQueue.flush]: genuine data 4xx
  /// (400/404/422 and any other non-retryable 4xx) → dropped + reported;
  /// 409 (ID_CONFLICT — already created by an id collision / earlier replay) →
  /// treated as success (idempotent win); 401/403/408/429/5xx/network → kept
  /// with exponential backoff.
  Future<BootstrapFlushResult> flush() {
    return _synchronized(() async {
      final key = await _key();
      var pending = await _loadAllForKey(key);
      // Rescue entries stranded under the anon key by an offline enqueue that
      // ran with a null stored user id.
      if (key != _anonKey) {
        final orphaned = await _loadAllForKey(_anonKey);
        if (orphaned.isNotEmpty) {
          pending = [...orphaned, ...pending];
          final p = await SharedPreferences.getInstance();
          await p.remove(_anonKey);
        }
      }
      if (pending.isEmpty) {
        return const BootstrapFlushResult(synced: 0, dropped: 0, deferred: 0);
      }
      final now = DateTime.now();
      var synced = 0;
      var dropped = 0;
      var deferred = 0;
      final remaining = <PendingBootstrapEntry>[];

      // Partition, preserving enqueue order within each op kind.
      final creates = [
        for (final e in pending) if (e.op == BootstrapOp.createWorkout) e,
      ];
      final adds = [
        for (final e in pending) if (e.op == BootstrapOp.addExercise) e,
      ];

      // workoutIds whose createWorkout hasn't successfully landed yet this run
      // (still queued, or it just failed/deferred). An addExercise against one
      // of these must NOT be sent — the parent workout may not exist yet.
      final blockedWorkoutIds = <String>{for (final e in creates) e.workoutId};
      // workoutIds whose createWorkout was permanently dropped (4xx). Their
      // exercises can never attach — drop them too instead of looping.
      final droppedWorkoutIds = <String>{};

      // ── Pass 1: createWorkout ops ──────────────────────────────────────────
      for (final e in creates) {
        if (e.nextRetryAt != null && e.nextRetryAt!.isAfter(now)) {
          remaining.add(e);
          deferred++;
          continue; // stays blocked
        }
        try {
          await _workouts.createWorkout(clientId: e.workoutId, label: e.label);
          synced++;
          blockedWorkoutIds.remove(e.workoutId);
        } on WorkoutApiException catch (err) {
          final outcome = _classify(err.statusCode);
          switch (outcome) {
            case _Outcome.success: // 409 — already created (idempotent win)
              synced++;
              blockedWorkoutIds.remove(e.workoutId);
            case _Outcome.drop:
              dropped++;
              blockedWorkoutIds.remove(e.workoutId);
              droppedWorkoutIds.add(e.workoutId);
              reportErrorNoStack(
                'offline bootstrap createWorkout dropped (${err.statusCode}): '
                'workout=${e.workoutId}',
                reason: 'offline-bootstrap:drop-4xx',
              );
            case _Outcome.keep:
              remaining.add(e._afterTransientFailure(now));
              deferred++;
          }
        } catch (_) {
          remaining.add(e._afterTransientFailure(now));
          deferred++;
        }
      }

      // ── Pass 2: addExercise ops ────────────────────────────────────────────
      for (final e in adds) {
        if (droppedWorkoutIds.contains(e.workoutId)) {
          dropped++;
          reportErrorNoStack(
            'offline bootstrap addExercise dropped (parent workout 4xx): '
            'workout=${e.workoutId} we=${e.weId}',
            reason: 'offline-bootstrap:drop-orphan',
          );
          continue;
        }
        if (blockedWorkoutIds.contains(e.workoutId)) {
          remaining.add(e);
          deferred++;
          continue;
        }
        if (e.nextRetryAt != null && e.nextRetryAt!.isAfter(now)) {
          remaining.add(e);
          deferred++;
          continue;
        }
        try {
          await _workouts.addExercise(
            e.workoutId,
            e.exerciseId!,
            position: e.position,
            clientId: e.weId,
          );
          synced++;
        } on WorkoutApiException catch (err) {
          final outcome = _classify(err.statusCode);
          switch (outcome) {
            case _Outcome.success: // 409 — already attached (idempotent win)
              synced++;
            case _Outcome.drop:
              dropped++;
              reportErrorNoStack(
                'offline bootstrap addExercise dropped (${err.statusCode}): '
                'workout=${e.workoutId} we=${e.weId}',
                reason: 'offline-bootstrap:drop-4xx',
              );
            case _Outcome.keep:
              remaining.add(e._afterTransientFailure(now));
              deferred++;
          }
        } catch (_) {
          remaining.add(e._afterTransientFailure(now));
          deferred++;
        }
      }

      await _saveForKey(key, remaining);
      return BootstrapFlushResult(
        synced: synced,
        dropped: dropped,
        deferred: deferred,
      );
    });
  }

  static _Outcome _classify(int statusCode) {
    // 409 ID_CONFLICT: the id already exists (collision / earlier replay landed).
    // The desired end state IS reached — treat as a clean success.
    if (statusCode == 409) return _Outcome.success;
    const retryable4xx = {401, 403, 408, 429};
    final permanent = statusCode >= 400 &&
        statusCode < 500 &&
        !retryable4xx.contains(statusCode);
    return permanent ? _Outcome.drop : _Outcome.keep;
  }
}

enum _Outcome { success, drop, keep }

class BootstrapFlushResult {
  const BootstrapFlushResult({
    required this.synced,
    required this.dropped,
    this.deferred = 0,
  });
  final int synced;
  final int dropped;

  /// Entries still queued — either inside a backoff window, or an addExercise
  /// held behind a parent createWorkout that hasn't landed yet.
  final int deferred;
}
