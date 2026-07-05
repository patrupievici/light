import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '_crash_reporter.dart';
import 'auth_service.dart';
import 'workout_service.dart';

/// The kind of mutation a [PendingSetEntry] replays on reconnect.
///
/// * [add]    — create the set (idempotent via `clientSetId`).
/// * [update] — patch weight/reps/rpe/completed of an existing set (`setId`).
/// * [delete] — remove an existing set (`setId`).
///
/// `add` is the only op that does NOT need a server-assigned `setId`: the set
/// may not exist server-side yet, so it's addressed purely by `clientSetId`.
/// `update`/`delete` target a concrete row by `setId` — UNLESS that row was
/// itself created by a still-pending `add` in the same queue, in which case the
/// add must flush first (see [OfflineSyncCoordinator]'s replay ordering).
enum PendingSetOp { add, update, delete }

PendingSetOp _parseOp(dynamic raw) {
  switch (raw) {
    case 'update':
      return PendingSetOp.update;
    case 'delete':
      return PendingSetOp.delete;
    default:
      // Legacy entries (queued before op typing) were always adds; default to
      // add so they replay exactly as before.
      return PendingSetOp.add;
  }
}

String _opToJson(PendingSetOp op) => switch (op) {
      PendingSetOp.add => 'add',
      PendingSetOp.update => 'update',
      PendingSetOp.delete => 'delete',
    };

/// Pending set mutation when offline or a request fails — flushed on reconnect.
///
/// Originally this only modelled the ADD path; it now carries an [op] so that
/// EDIT and DELETE survive offline too (previously an offline edit was wrongly
/// re-enqueued as a fresh ADD, duplicating the set). For `add`, `weightKg` and
/// `reps` are the payload and `setId` is null. For `update`, the non-null
/// payload fields are the patch and `setId` points at the row to patch. For
/// `delete`, only `setId` matters.
class PendingSetEntry {
  const PendingSetEntry({
    required this.workoutId,
    required this.weId,
    required this.clientSetId,
    this.op = PendingSetOp.add,
    this.setId,
    this.weightKg = 0,
    this.reps = 1,
    this.rpe,
    this.tag = 'WORK',
    this.note,
    this.queuedAt,
    this.retryCount = 0,
    this.nextRetryAt,
  });

  /// Convenience builder for the original ADD path — keeps existing callers
  /// terse and makes the op explicit at the call site.
  factory PendingSetEntry.add({
    required String workoutId,
    required String weId,
    required double weightKg,
    required int reps,
    required String clientSetId,
    double? rpe,
    String tag = 'WORK',
    String? note,
    DateTime? queuedAt,
  }) =>
      PendingSetEntry(
        workoutId: workoutId,
        weId: weId,
        clientSetId: clientSetId,
        op: PendingSetOp.add,
        weightKg: weightKg,
        reps: reps,
        rpe: rpe,
        tag: tag,
        note: note,
        queuedAt: queuedAt,
      );

  /// EDIT path: patch an existing set identified by [setId]. [clientSetId] ties
  /// this op back to the set's ADD entry so replay can order add-before-update
  /// when the set was created offline in the same session.
  factory PendingSetEntry.update({
    required String workoutId,
    required String weId,
    required String setId,
    required String clientSetId,
    required double weightKg,
    required int reps,
    double? rpe,
    String? note,
    DateTime? queuedAt,
  }) =>
      PendingSetEntry(
        workoutId: workoutId,
        weId: weId,
        clientSetId: clientSetId,
        op: PendingSetOp.update,
        setId: setId,
        weightKg: weightKg,
        reps: reps,
        rpe: rpe,
        note: note,
        queuedAt: queuedAt,
      );

  /// DELETE path: remove an existing set identified by [setId].
  factory PendingSetEntry.delete({
    required String workoutId,
    required String weId,
    required String setId,
    required String clientSetId,
    DateTime? queuedAt,
  }) =>
      PendingSetEntry(
        workoutId: workoutId,
        weId: weId,
        clientSetId: clientSetId,
        op: PendingSetOp.delete,
        setId: setId,
        queuedAt: queuedAt,
      );

  final String workoutId;
  final String weId;
  /// What to replay: add | update | delete.
  final PendingSetOp op;
  /// Server-assigned set id, for `update`/`delete`. Null for `add`.
  final String? setId;
  final double weightKg;
  final int reps;
  final double? rpe;
  final String tag;
  /// Anti-cheat justification note carried with a >2× weight-jump set so an
  /// offline replay re-sends the same justification the user already gave.
  final String? note;
  final DateTime? queuedAt;
  /// Idempotency token: re-sending the same one returns the existing set.
  /// Shared between an `add` and any `update`/`delete` of the SAME set so the
  /// coordinator can keep a child op behind its parent add during replay.
  final String clientSetId;

  /// How many transient (5xx/network) failures this entry has hit, and the
  /// earliest time we should retry it again — used for exponential backoff so a
  /// reconnect during a backend outage doesn't hammer the recovering server.
  final int retryCount;
  final DateTime? nextRetryAt;

  PendingSetEntry _afterTransientFailure(DateTime now) {
    final next = retryCount + 1;
    // 2^n seconds, capped at 30 min.
    final delaySec = (1 << (next.clamp(0, 11))).clamp(2, 1800);
    return PendingSetEntry(
      workoutId: workoutId,
      weId: weId,
      op: op,
      setId: setId,
      weightKg: weightKg,
      reps: reps,
      clientSetId: clientSetId,
      rpe: rpe,
      tag: tag,
      note: note,
      queuedAt: queuedAt,
      retryCount: next,
      nextRetryAt: now.add(Duration(seconds: delaySec)),
    );
  }

  Map<String, dynamic> toJson() => {
        'workoutId': workoutId,
        'weId': weId,
        // Omit for adds so legacy/add JSON stays byte-identical to before.
        if (op != PendingSetOp.add) 'op': _opToJson(op),
        if (setId != null) 'setId': setId,
        'weightKg': weightKg,
        'reps': reps,
        if (rpe != null) 'rpe': rpe,
        'tag': tag,
        if (note != null) 'note': note,
        'clientSetId': clientSetId,
        'queuedAt': (queuedAt ?? DateTime.now()).toIso8601String(),
        if (retryCount > 0) 'retryCount': retryCount,
        if (nextRetryAt != null) 'nextRetryAt': nextRetryAt!.toIso8601String(),
      };

  static PendingSetEntry? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final wId = m['workoutId'] as String?;
    final weId = m['weId'] as String?;
    if (wId == null || weId == null) return null;
    final op = _parseOp(m['op']);
    final setId = m['setId'] as String?;
    // update/delete address a concrete row — drop the entry if it has no setId
    // (it can never be replayed and would loop / be ambiguous forever).
    if (op != PendingSetOp.add && (setId == null || setId.isEmpty)) return null;
    final weightKg = (m['weightKg'] as num?)?.toDouble() ?? 0;
    final reps = (m['reps'] as num?)?.toInt() ?? 1;
    final rpe = (m['rpe'] as num?)?.toDouble();
    final tag = m['tag'] as String? ?? 'WORK';
    final note = m['note'] as String?;
    final queuedAt =
        m['queuedAt'] != null ? DateTime.tryParse(m['queuedAt'] as String) : null;
    // Legacy entries (queued before clientSetId existed) get a DETERMINISTIC id
    // derived from their content — re-deriving it on every load yields the same
    // token, so a failed flush can't create duplicates by minting a fresh UUID
    // each app restart (the server dedupes on clientSetId).
    final clientSetId = (m['clientSetId'] as String?) ??
        'legacy-$wId-$weId-$weightKg-$reps-${rpe ?? 'n'}-$tag-'
            '${queuedAt?.millisecondsSinceEpoch ?? 0}';
    return PendingSetEntry(
      workoutId: wId,
      weId: weId,
      op: op,
      setId: setId,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe,
      tag: tag,
      note: note,
      clientSetId: clientSetId,
      queuedAt: queuedAt,
      retryCount: (m['retryCount'] as num?)?.toInt() ?? 0,
      nextRetryAt: m['nextRetryAt'] != null
          ? DateTime.tryParse(m['nextRetryAt'] as String)
          : null,
    );
  }
}

class OfflineSetQueue {
  OfflineSetQueue({AuthService? auth, WorkoutService? workouts})
      : _auth = auth ?? AuthService(),
        _workouts = workouts ?? WorkoutService();

  final AuthService _auth;
  final WorkoutService _workouts;

  static const _keyPrefix = 'zvelt_offline_set_queue_v1';

  /// Schema version of the PERSISTED envelope (not the storage key). Bump this
  /// only when [_migrateRaw] can no longer round-trip an older shape verbatim;
  /// add a migration branch when you do. The on-disk format is:
  ///
  ///     { "schemaVersion": <int>, "entries": [ <entry>, ... ] }
  ///
  /// Older builds wrote a BARE top-level JSON array (no envelope). [_migrateRaw]
  /// detects that and treats it as schemaVersion 1 so historical queued ops are
  /// MIGRATED forward instead of being silently dropped on first load by a build
  /// that expects the envelope.
  static const int currentSchemaVersion = 2;

  /// Hard cap on queued entries. A permanently-failing op (e.g. a 5xx that never
  /// clears) must not let the queue grow without bound and blow the
  /// SharedPreferences value size. When exceeded we drop the OLDEST entries
  /// (closest to expiry / least likely to still matter) and report each drop.
  static const int maxEntries = 500;

  /// Entries older than this are condensed out of the queue on load/save. A set
  /// that has been failing to sync for two weeks is almost certainly tied to a
  /// workout the user has moved on from; keeping it forever only bloats storage
  /// and re-hammers the backend. Drops are reported, never silent.
  static const Duration entryTtl = Duration(days: 14);

  /// Serializes all queue mutations (enqueue/flush) so their read-modify-write
  /// cycles never interleave — otherwise two concurrent offline logs can race
  /// and one gets clobbered by the other's stale snapshot.
  Future<void> _lock = Future.value();

  /// Runs [action] after any in-flight mutation completes, chaining the next
  /// mutation onto the same tail. Failures don't break the chain.
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    // Chain onto the current tail; swallow prior errors so the lock survives.
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<String> _key() async {
    final id = await _auth.getCurrentUserId();
    return '${_keyPrefix}_${id ?? 'anon'}';
  }

  Future<List<PendingSetEntry>> _loadAllForKey(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return [];
    List<PendingSetEntry> entries;
    try {
      entries = _decodeEnvelope(raw);
    } catch (_) {
      return [];
    }
    // Enforce TTL + cap on every read so a build that only ever reads (e.g. a
    // pendingCount poll) still surfaces the true, prunable count. Pruning here
    // does not persist — the next save() writes the pruned set.
    return _prune(entries, DateTime.now());
  }

  /// Decode the persisted value, migrating older shapes forward so a format
  /// change MIGRATES queued ops instead of dropping them.
  ///
  /// Accepts two shapes:
  ///   * legacy (schemaVersion 1): a bare top-level JSON array of entries;
  ///   * current (schemaVersion ≥ 2): `{ schemaVersion, entries: [...] }`.
  ///
  /// Unknown FUTURE versions (written by a newer build, then opened by an older
  /// one) are read on a best-effort basis via the same per-entry [fromJson],
  /// which already tolerates unknown keys — so a forward/back hop never wipes
  /// the queue.
  static List<PendingSetEntry> _decodeEnvelope(String raw) {
    final decoded = jsonDecode(raw);
    final list = _migrateRaw(decoded);
    return list
        .map(PendingSetEntry.fromJson)
        .whereType<PendingSetEntry>()
        .toList();
  }

  /// Returns the raw entry maps after applying any schema migration. Pure +
  /// synchronous so it is unit-testable without SharedPreferences.
  static List<dynamic> _migrateRaw(dynamic decoded) {
    // Legacy: a bare array == schemaVersion 1. Treat each element as an entry.
    if (decoded is List) {
      return _migrateEntriesFromV1(decoded);
    }
    if (decoded is Map) {
      final version = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;
      final entries = decoded['entries'];
      if (entries is! List) return const [];
      // Step migrations forward, version by version. Each step is a verbatim
      // pass today (the entry shape itself is backward-compatible via
      // fromJson), but the ladder is here so a real shape change only has to
      // add one branch — old entries flow through every step instead of being
      // dropped.
      var current = entries;
      var v = version;
      while (v < currentSchemaVersion) {
        current = switch (v) {
          1 => _migrateEntriesFromV1(current),
          _ => current,
        };
        v++;
      }
      return current;
    }
    return const [];
  }

  /// v1 → v2 entry migration. The on-disk entry map did not change between the
  /// two versions (v2 only introduced the envelope + TTL/cap), so this is an
  /// identity pass; it exists so the migration ladder has a real first rung and
  /// a future v2 → v3 entry reshape has an obvious template to copy.
  static List<dynamic> _migrateEntriesFromV1(List<dynamic> entries) => entries;

  /// Drop expired (older than [entryTtl]) and over-cap entries, reporting each
  /// removal so a silently-discarded set is observable. Order is preserved for
  /// the survivors (replay ordering — parent-before-child — depends on it).
  static List<PendingSetEntry> _prune(
    List<PendingSetEntry> entries,
    DateTime now,
  ) {
    if (entries.isEmpty) return entries;
    final cutoff = now.subtract(entryTtl);
    final kept = <PendingSetEntry>[];
    for (final e in entries) {
      final queuedAt = e.queuedAt;
      if (queuedAt != null && queuedAt.isBefore(cutoff)) {
        reportErrorNoStack(
          'offline ${_opToJson(e.op)} dropped (ttl ${entryTtl.inDays}d): '
          'we=${e.weId} set=${e.setId} queuedAt=${queuedAt.toIso8601String()}',
          reason: 'offline-queue:drop-ttl',
        );
        continue;
      }
      kept.add(e);
    }
    // Cap: keep the NEWEST [maxEntries] (drop oldest first). Entries are in
    // enqueue order, so the head is oldest.
    if (kept.length > maxEntries) {
      final overflow = kept.length - maxEntries;
      for (var i = 0; i < overflow; i++) {
        final e = kept[i];
        reportErrorNoStack(
          'offline ${_opToJson(e.op)} dropped (cap $maxEntries exceeded): '
          'we=${e.weId} set=${e.setId}',
          reason: 'offline-queue:drop-cap',
        );
      }
      return kept.sublist(overflow);
    }
    return kept;
  }

  Future<List<PendingSetEntry>> loadAll() async => _loadAllForKey(await _key());

  Future<int> pendingCount() async => (await loadAll()).length;

  Future<void> enqueue(PendingSetEntry entry) {
    return _synchronized(() async {
      // Resolve the storage key ONCE and reuse it for the final write, so a
      // mid-op user/token flip can't orphan the entry under a different key.
      final key = await _key();
      final all = await _loadAllForKey(key);
      all.add(entry);
      // Re-prune after the add so the cap is enforced AT WRITE TIME (the +1 may
      // push a full queue one over); _loadAllForKey already pruned the existing
      // set, so the only newly-prunable case here is the cap.
      await _saveForKey(key, _prune(all, DateTime.now()));
    });
  }

  Future<void> _saveForKey(String key, List<PendingSetEntry> entries) async {
    final p = await SharedPreferences.getInstance();
    // Persist the versioned envelope so a future shape change can MIGRATE these
    // entries on read instead of dropping them. (Older builds that expect a bare
    // array will fail to parse and fall back to an empty queue — acceptable, as
    // downgrades are not a supported path; forward migration is.)
    await p.setString(
      key,
      jsonEncode({
        'schemaVersion': currentSchemaVersion,
        'entries': entries.map((e) => e.toJson()).toList(),
      }),
    );
  }

  /// Replay a single queued op against the backend. Dispatches by [op] so an
  /// offline EDIT patches the existing set (instead of the old behaviour of
  /// re-creating it as a duplicate ADD). Throws on failure exactly like the
  /// underlying [WorkoutService] call, so [flush]'s 4xx-drop / 5xx-backoff
  /// handling applies uniformly to every op type.
  Future<void> _replay(PendingSetEntry e) async {
    switch (e.op) {
      case PendingSetOp.add:
        await _workouts.addSet(
          e.workoutId,
          e.weId,
          weightKg: e.weightKg,
          reps: e.reps,
          rpe: e.rpe,
          tag: e.tag,
          clientSetId: e.clientSetId,
          note: e.note,
        );
      case PendingSetOp.update:
        // setId is guaranteed non-null for update (enforced in fromJson and the
        // PendingSetEntry.update factory).
        await _workouts.updateSet(
          e.workoutId,
          e.weId,
          e.setId!,
          weightKg: e.weightKg,
          reps: e.reps,
          rpe: e.rpe,
          isCompleted: true,
          note: e.note,
        );
      case PendingSetOp.delete:
        // setId is guaranteed non-null for delete (enforced in fromJson and
        // the PendingSetEntry.delete factory). deleteSet treats a 404 as
        // success — the set being already gone IS the desired end state, so a
        // replay against an already-removed row syncs clean instead of being
        // dropped as a 4xx.
        await _workouts.deleteSet(e.workoutId, e.weId, e.setId!);
    }
  }

  /// Try to flush all pending sets. Returns the number successfully synced,
  /// the number dropped (4xx — un-retryable), and how many were deferred
  /// (still in backoff). Entries the server rejected with 4xx are dropped (and
  /// reported to Crashlytics, since a silently discarded set is data loss the
  /// user should be able to learn about), keeping them would loop forever.
  /// Transient (5xx/network) failures stay queued with exponential backoff so a
  /// reconnect during an outage doesn't hammer the recovering backend.
  Future<FlushResult> flush() {
    return _synchronized(() async {
      // Resolve the storage key ONCE up front and reuse it for the final write,
      // so a mid-flush user/token flip (e.g. refresh → 'anon') can't make the
      // remaining (unsynced) entries get written under the wrong user key.
      final key = await _key();
      final pending = await _loadAllForKey(key);
      if (pending.isEmpty) return const FlushResult(synced: 0, dropped: 0, deferred: 0);
      final now = DateTime.now();
      var synced = 0;
      var dropped = 0;
      var deferred = 0;
      final remaining = <PendingSetEntry>[];
      // clientSetIds whose parent `add` hasn't successfully flushed yet this run
      // (either still queued from a prior session, or it just failed/deferred
      // above). A child `update`/`delete` referencing one of these MUST NOT be
      // sent — the target set may not exist server-side, so the patch would 404
      // and (worse, for 4xx) be dropped. We hold the child back so it replays in
      // a later flush, after its parent add lands. Set ordering: `pending` is in
      // enqueue order, so every parent add precedes its children here.
      final blockedClientSetIds = <String>{
        for (final e in pending)
          if (e.op == PendingSetOp.add) e.clientSetId,
      };
      // clientSetIds whose parent `add` was permanently dropped (4xx) this run.
      // The set never reached the server, so its queued children can't target
      // anything — drop them too instead of deferring them forever.
      final orphanedClientSetIds = <String>{};
      for (final e in pending) {
        // A child whose parent add was just dropped (4xx) is orphaned — there's
        // no row to update/delete, so drop it rather than loop forever.
        if (e.op != PendingSetOp.add &&
            orphanedClientSetIds.contains(e.clientSetId)) {
          dropped++;
          reportErrorNoStack(
            'offline ${_opToJson(e.op)} dropped (orphaned add): we=${e.weId} set=${e.setId}',
            reason: 'offline-queue:drop-orphan',
          );
          continue;
        }
        // Respect exponential backoff — don't retry until the window elapses.
        if (e.nextRetryAt != null && e.nextRetryAt!.isAfter(now)) {
          remaining.add(e);
          deferred++;
          if (e.op == PendingSetOp.add) blockedClientSetIds.add(e.clientSetId);
          continue;
        }
        // Hold a child op behind a still-unflushed parent add (see above).
        if (e.op != PendingSetOp.add &&
            blockedClientSetIds.contains(e.clientSetId)) {
          remaining.add(e);
          deferred++;
          continue;
        }
        try {
          await _replay(e);
          synced++;
          // Parent add landed — its children are now safe to flush this run.
          if (e.op == PendingSetOp.add) {
            blockedClientSetIds.remove(e.clientSetId);
          }
        } on WorkoutApiException catch (err) {
          // 4xx = client/data error; a retry will never succeed — drop, but
          // record it so a silently-lost set is at least observable.
          if (err.statusCode >= 400 && err.statusCode < 500) {
            dropped++;
            // If a parent add is un-retryable, its children are orphaned too.
            if (e.op == PendingSetOp.add) {
              orphanedClientSetIds.add(e.clientSetId);
            }
            reportErrorNoStack(
              'offline ${_opToJson(e.op)} dropped (${err.statusCode}): we=${e.weId} reps=${e.reps} wkg=${e.weightKg}',
              reason: 'offline-queue:drop-4xx',
            );
          } else {
            remaining.add(e._afterTransientFailure(now));
          }
        } on WeightJumpNoteRequiredException catch (_) {
          // A >2× weight jump the server won't accept without a justification
          // note. A background flush can't prompt the user, so retrying loops
          // forever — drop it like a 4xx (and orphan its children), recording it
          // so the discarded set is observable. (When the note WAS captured
          // online it rides along in e.note and this branch never fires.)
          dropped++;
          if (e.op == PendingSetOp.add) {
            orphanedClientSetIds.add(e.clientSetId);
          }
          reportErrorNoStack(
            'offline ${_opToJson(e.op)} dropped (weight-jump needs note): we=${e.weId} wkg=${e.weightKg}',
            reason: 'offline-queue:drop-weight-jump',
          );
        } catch (_) {
          // Network error or timeout — keep with backoff for the next attempt.
          remaining.add(e._afterTransientFailure(now));
        }
      }
      await _saveForKey(key, remaining);
      return FlushResult(synced: synced, dropped: dropped, deferred: deferred);
    });
  }
}

class FlushResult {
  const FlushResult({required this.synced, required this.dropped, this.deferred = 0});
  final int synced;
  final int dropped;
  /// Entries still queued because their backoff window hasn't elapsed.
  final int deferred;
}
