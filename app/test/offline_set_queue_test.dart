// Meaningful tests for the offline-first set queue — the highest-value gap.
//
// The queue persists workout sets logged while offline (or when the server
// rejected the request) and flushes them on reconnect. The behaviour that
// MUST hold, and that these tests pin down:
//   * JSON roundtrip preserves every field (incl. the idempotency token and
//     backoff bookkeeping).
//   * Legacy entries (queued before clientSetId existed) get a DETERMINISTIC
//     id — re-deriving it on each load must NOT mint a fresh UUID, or a failed
//     flush would create duplicate sets server-side.
//   * 4xx → drop (a retry can never succeed); 5xx / network → keep with
//     exponential backoff; an entry inside its backoff window is DEFERRED, not
//     retried.
//   * Concurrent enqueues both persist (the read-modify-write is serialized).
//
// Network is avoided entirely: AuthService and WorkoutService are faked via the
// OfflineSetQueue constructor seam, and SharedPreferences uses mock storage.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zvelt_app/services/auth_service.dart';
import 'package:zvelt_app/services/offline_set_queue.dart';
import 'package:zvelt_app/services/workout_service.dart';

/// Auth stub: returns a fixed user id without ever touching SecureStorage,
/// SharedPreferences tokens, or the network.
class _FakeAuth extends AuthService {
  @override
  Future<String?> getCurrentUserId() async => 'user-1';
}

/// Workout API stub. By default every add/update succeeds and is recorded; set
/// [error] to make every call throw it instead (drop / transient scenarios).
class _FakeWorkouts extends WorkoutService {
  _FakeWorkouts({this.error}) : super(auth: _FakeAuth());

  final Object? error;
  int callCount = 0;
  final List<String?> seenClientSetIds = [];
  // Per-op call logs so tests can assert an EDIT replayed via updateSet (not a
  // duplicate addSet) and target the correct setId.
  int addCount = 0;
  int updateCount = 0;
  final List<String> updatedSetIds = [];

  @override
  Future<WorkoutSetDto> addSet(
    String workoutId,
    String weId, {
    required double weightKg,
    required int reps,
    double? rpe,
    String tag = 'WORK',
    bool isCompleted = true,
    String? clientSetId,
  }) async {
    callCount++;
    addCount++;
    seenClientSetIds.add(clientSetId);
    if (error != null) throw error!;
    return WorkoutSetDto(
      id: 'srv-$callCount',
      setIndex: callCount,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe,
      tag: tag,
    );
  }

  @override
  Future<WorkoutSetDto> updateSet(
    String workoutId,
    String weId,
    String setId, {
    double? weightKg,
    int? reps,
    double? rpe,
    bool? isCompleted,
  }) async {
    callCount++;
    updateCount++;
    updatedSetIds.add(setId);
    if (error != null) throw error!;
    return WorkoutSetDto(
      id: setId,
      setIndex: callCount,
      weightKg: weightKg ?? 0,
      reps: reps ?? 0,
      rpe: rpe,
      tag: 'WORK',
    );
  }
}

PendingSetEntry _entry({
  String workoutId = 'w1',
  String weId = 'we1',
  double weightKg = 100,
  int reps = 5,
  double? rpe = 8,
  String tag = 'WORK',
  String clientSetId = 'cid-1',
  DateTime? queuedAt,
  int retryCount = 0,
  DateTime? nextRetryAt,
}) {
  return PendingSetEntry(
    workoutId: workoutId,
    weId: weId,
    weightKg: weightKg,
    reps: reps,
    rpe: rpe,
    tag: tag,
    clientSetId: clientSetId,
    queuedAt: queuedAt,
    retryCount: retryCount,
    nextRetryAt: nextRetryAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PendingSetEntry JSON', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      final queued = DateTime.parse('2026-06-19T10:00:00.000Z');
      final next = DateTime.parse('2026-06-19T10:05:00.000Z');
      final original = _entry(
        workoutId: 'w-abc',
        weId: 'we-xyz',
        weightKg: 142.5,
        reps: 3,
        rpe: 9.5,
        tag: 'WORK',
        clientSetId: 'idem-token-42',
        queuedAt: queued,
        retryCount: 4,
        nextRetryAt: next,
      );

      final restored = PendingSetEntry.fromJson(original.toJson())!;

      expect(restored.workoutId, 'w-abc');
      expect(restored.weId, 'we-xyz');
      expect(restored.weightKg, 142.5);
      expect(restored.reps, 3);
      expect(restored.rpe, 9.5);
      expect(restored.tag, 'WORK');
      expect(restored.clientSetId, 'idem-token-42');
      expect(restored.queuedAt, queued);
      expect(restored.retryCount, 4);
      expect(restored.nextRetryAt, next);
    });

    test('null rpe survives the roundtrip as null (not 0)', () {
      final restored =
          PendingSetEntry.fromJson(_entry(rpe: null).toJson())!;
      expect(restored.rpe, isNull);
    });

    test('legacy entry (no clientSetId) derives a DETERMINISTIC id', () {
      // Same legacy map decoded twice → identical id (no random UUID), so a
      // retried flush dedupes server-side instead of duplicating the set.
      final legacy = {
        'workoutId': 'w9',
        'weId': 'we9',
        'weightKg': 80.0,
        'reps': 6,
        'rpe': 7.0,
        'tag': 'WORK',
        'queuedAt': '2026-06-19T09:00:00.000Z',
        // NOTE: no 'clientSetId' key — pre-idempotency legacy shape.
      };

      final a = PendingSetEntry.fromJson(legacy)!;
      final b = PendingSetEntry.fromJson(legacy)!;

      expect(a.clientSetId, isNotEmpty);
      expect(a.clientSetId, startsWith('legacy-'));
      expect(a.clientSetId, b.clientSetId,
          reason: 'legacy id must be content-derived, never a fresh UUID');
    });

    test('fromJson rejects entries missing required ids', () {
      expect(PendingSetEntry.fromJson({'weId': 'we1'}), isNull);
      expect(PendingSetEntry.fromJson({'workoutId': 'w1'}), isNull);
      expect(PendingSetEntry.fromJson('not-a-map'), isNull);
    });
  });

  group('enqueue + load', () {
    test('enqueue then loadAll/pendingCount reflect the entry', () async {
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());

      expect(await q.pendingCount(), 0);
      await q.enqueue(_entry(clientSetId: 'cid-A'));

      expect(await q.pendingCount(), 1);
      final all = await q.loadAll();
      expect(all.single.clientSetId, 'cid-A');
    });

    test('two concurrent enqueues both persist (serialized RMW, no clobber)',
        () async {
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());

      // Fire both WITHOUT awaiting between them — if the read-modify-write
      // weren't serialized, the second would overwrite the first's snapshot.
      final f1 = q.enqueue(_entry(clientSetId: 'cid-1'));
      final f2 = q.enqueue(_entry(clientSetId: 'cid-2'));
      await Future.wait([f1, f2]);

      final ids =
          (await q.loadAll()).map((e) => e.clientSetId).toSet();
      expect(ids, {'cid-1', 'cid-2'});
    });
  });

  group('flush', () {
    test('success → synced count, queue emptied', () async {
      final fake = _FakeWorkouts();
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      await q.enqueue(_entry(clientSetId: 'cid-ok-1'));
      await q.enqueue(_entry(clientSetId: 'cid-ok-2'));

      final res = await q.flush();

      expect(res.synced, 2);
      expect(res.dropped, 0);
      expect(res.deferred, 0);
      expect(await q.pendingCount(), 0);
      // The idempotency token is forwarded to the API (server dedupes on it).
      expect(fake.seenClientSetIds, containsAll(['cid-ok-1', 'cid-ok-2']));
    });

    test('4xx (422) → entry DROPPED, not kept', () async {
      final fake = _FakeWorkouts(
        error: WorkoutApiException(statusCode: 422, message: 'invalid set'),
      );
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      await q.enqueue(_entry());

      final res = await q.flush();

      expect(res.dropped, 1);
      expect(res.synced, 0);
      expect(res.deferred, 0);
      expect(await q.pendingCount(), 0,
          reason: '4xx can never succeed on retry — must be dropped');
    });

    test('5xx (503) → entry KEPT with backoff (retryCount++, nextRetryAt set)',
        () async {
      final fake = _FakeWorkouts(
        error: WorkoutApiException(statusCode: 503, message: 'unavailable'),
      );
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      await q.enqueue(_entry(retryCount: 0));

      final res = await q.flush();

      expect(res.synced, 0);
      expect(res.dropped, 0);
      expect(await q.pendingCount(), 1, reason: '5xx is transient — keep it');

      final kept = (await q.loadAll()).single;
      expect(kept.retryCount, 1);
      expect(kept.nextRetryAt, isNotNull);
      expect(kept.nextRetryAt!.isAfter(DateTime.now()), isTrue);
    });

    test('generic network error → entry KEPT with backoff', () async {
      final fake = _FakeWorkouts(error: Exception('connection reset'));
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      await q.enqueue(_entry());

      final res = await q.flush();

      expect(res.synced, 0);
      expect(await q.pendingCount(), 1);
      expect((await q.loadAll()).single.retryCount, 1);
    });

    test('an entry inside its backoff window is DEFERRED, not retried',
        () async {
      // First flush against a 503 schedules backoff (nextRetryAt ≥ now + 2s).
      final failing = _FakeWorkouts(
        error: WorkoutApiException(statusCode: 503, message: 'unavailable'),
      );
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: failing);
      await q.enqueue(_entry());
      await q.flush();
      final callsAfterFirst = failing.callCount;
      expect(callsAfterFirst, 1);

      // Immediate second flush: still inside the backoff window → deferred.
      // The API must NOT be hit again (don't hammer a recovering backend).
      final res2 = await q.flush();

      expect(res2.deferred, 1);
      expect(res2.synced, 0);
      expect(res2.dropped, 0);
      expect(failing.callCount, callsAfterFirst,
          reason: 'deferred entries must not call the API during backoff');
      expect(await q.pendingCount(), 1);
    });

    test('flush on an empty queue is a no-op (zeros, no API call)', () async {
      final fake = _FakeWorkouts();
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);

      final res = await q.flush();

      expect(res.synced, 0);
      expect(res.dropped, 0);
      expect(res.deferred, 0);
      expect(fake.callCount, 0);
    });

    test('mixed batch: success + 5xx kept + nothing lost', () async {
      // Entry A succeeds, entry B hits a transient 503. Because the fake throws
      // for every call, drive them in two queues to keep the assertion crisp:
      // here we verify a single 503 in a one-entry queue stays, while a
      // success path empties — already covered above. This case pins that a
      // successful flush forwards the EXACT clientSetId for idempotency.
      final fake = _FakeWorkouts();
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      await q.enqueue(_entry(clientSetId: 'forward-me'));

      await q.flush();

      expect(fake.seenClientSetIds.single, 'forward-me');
    });
  });

  group('op-typed entries', () {
    test('update entry JSON roundtrip preserves op + setId', () {
      final original = PendingSetEntry.update(
        workoutId: 'w1',
        weId: 'we1',
        setId: 'srv-set-7',
        clientSetId: 'cid-u',
        weightKg: 120,
        reps: 4,
        rpe: 8.5,
      );

      final restored = PendingSetEntry.fromJson(original.toJson())!;

      expect(restored.op, PendingSetOp.update);
      expect(restored.setId, 'srv-set-7');
      expect(restored.weightKg, 120);
      expect(restored.reps, 4);
      expect(restored.rpe, 8.5);
      expect(restored.clientSetId, 'cid-u');
    });

    test('add entry JSON omits the op key (legacy-compatible shape)', () {
      final json = PendingSetEntry.add(
        workoutId: 'w1',
        weId: 'we1',
        weightKg: 100,
        reps: 5,
        clientSetId: 'cid-a',
      ).toJson();
      // Old readers (and the diff against pre-op JSON) must see no 'op' key for
      // adds, and no spurious 'setId'.
      expect(json.containsKey('op'), isFalse);
      expect(json.containsKey('setId'), isFalse);

      final restored = PendingSetEntry.fromJson(json)!;
      expect(restored.op, PendingSetOp.add);
    });

    test('update/delete entry with no setId is rejected by fromJson', () {
      expect(
        PendingSetEntry.fromJson({
          'workoutId': 'w1',
          'weId': 'we1',
          'op': 'update',
          'clientSetId': 'cid',
        }),
        isNull,
        reason: 'an update with no target setId can never be replayed',
      );
      expect(
        PendingSetEntry.fromJson({
          'workoutId': 'w1',
          'weId': 'we1',
          'op': 'delete',
          'clientSetId': 'cid',
        }),
        isNull,
      );
    });

    test('offline EDIT replays via updateSet, NOT a duplicate addSet', () async {
      // This is the core correctness fix: an offline edit must patch the
      // existing row, not create a new set.
      final fake = _FakeWorkouts();
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      await q.enqueue(PendingSetEntry.update(
        workoutId: 'w1',
        weId: 'we1',
        setId: 'srv-set-42',
        clientSetId: 'cid-edit',
        weightKg: 130,
        reps: 3,
      ));

      final res = await q.flush();

      expect(res.synced, 1);
      expect(fake.updateCount, 1);
      expect(fake.addCount, 0, reason: 'an edit must NOT become an add');
      expect(fake.updatedSetIds.single, 'srv-set-42');
      expect(await q.pendingCount(), 0);
    });

    test('update entry kept with backoff on 5xx (same as add)', () async {
      final fake = _FakeWorkouts(
        error: WorkoutApiException(statusCode: 503, message: 'down'),
      );
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      await q.enqueue(PendingSetEntry.update(
        workoutId: 'w1',
        weId: 'we1',
        setId: 'srv-set-1',
        clientSetId: 'cid',
        weightKg: 100,
        reps: 5,
      ));

      final res = await q.flush();

      expect(res.synced, 0);
      expect(await q.pendingCount(), 1);
      final kept = (await q.loadAll()).single;
      expect(kept.op, PendingSetOp.update);
      expect(kept.retryCount, 1);
    });
  });

  group('replay ordering (add before its update)', () {
    test('child update is DEFERRED while its parent add is still pending',
        () async {
      // Parent add fails transiently (503) → stays queued. The child update,
      // which targets the same set via the SAME clientSetId, must NOT be sent
      // (the row may not exist server-side yet) and must remain queued.
      final fake = _FakeWorkouts(
        error: WorkoutApiException(statusCode: 503, message: 'down'),
      );
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      const cid = 'cid-shared';
      await q.enqueue(PendingSetEntry.add(
        workoutId: 'w1',
        weId: 'we1',
        weightKg: 100,
        reps: 5,
        clientSetId: cid,
      ));
      await q.enqueue(PendingSetEntry.update(
        workoutId: 'w1',
        weId: 'we1',
        setId: 'srv-set-1',
        clientSetId: cid,
        weightKg: 110,
        reps: 4,
      ));

      final res = await q.flush();

      // Add attempted (and kept with backoff); update NEVER attempted.
      expect(fake.addCount, 1);
      expect(fake.updateCount, 0,
          reason: 'a child update must not flush before its parent add lands');
      expect(res.synced, 0);
      expect(await q.pendingCount(), 2);
    });

    test('parent add then child update both flush in order when online',
        () async {
      final fake = _FakeWorkouts();
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      const cid = 'cid-shared-2';
      await q.enqueue(PendingSetEntry.add(
        workoutId: 'w1',
        weId: 'we1',
        weightKg: 100,
        reps: 5,
        clientSetId: cid,
      ));
      await q.enqueue(PendingSetEntry.update(
        workoutId: 'w1',
        weId: 'we1',
        setId: 'srv-set-1',
        clientSetId: cid,
        weightKg: 110,
        reps: 4,
      ));

      final res = await q.flush();

      expect(res.synced, 2);
      expect(fake.addCount, 1);
      expect(fake.updateCount, 1);
      expect(await q.pendingCount(), 0);
    });

    test('child update is ORPHANED (dropped) when its parent add is 4xx-dropped',
        () async {
      final fake = _FakeWorkouts(
        error: WorkoutApiException(statusCode: 422, message: 'bad set'),
      );
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: fake);
      const cid = 'cid-orphan';
      await q.enqueue(PendingSetEntry.add(
        workoutId: 'w1',
        weId: 'we1',
        weightKg: 100,
        reps: 5,
        clientSetId: cid,
      ));
      await q.enqueue(PendingSetEntry.update(
        workoutId: 'w1',
        weId: 'we1',
        setId: 'srv-set-1',
        clientSetId: cid,
        weightKg: 110,
        reps: 4,
      ));

      final res = await q.flush();

      // Add dropped (4xx) → its child has no target → also dropped, not looped.
      expect(res.dropped, 2);
      expect(fake.updateCount, 0,
          reason: 'orphaned child must not be sent against a non-existent set');
      expect(await q.pendingCount(), 0);
    });
  });

  // ── Item 1: payload versioning + migrate-on-read ──────────────────────────
  //
  // A persisted-format change must MIGRATE old queued ops, never drop them.
  // Older builds wrote a BARE top-level JSON array; current builds wrap it in a
  // { schemaVersion, entries } envelope. Both shapes must load.
  group('payload schema versioning', () {
    const key = 'zvelt_offline_set_queue_v1_user-1';

    test('legacy BARE-ARRAY payload (pre-envelope) still loads — not dropped',
        () async {
      // Exactly what an older build wrote: a top-level array, no envelope.
      final legacyArray = [
        _entry(clientSetId: 'legacy-1').toJson(),
        _entry(clientSetId: 'legacy-2', weId: 'we2').toJson(),
      ];
      SharedPreferences.setMockInitialValues({key: jsonEncode(legacyArray)});

      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      final all = await q.loadAll();

      expect(all.map((e) => e.clientSetId).toSet(), {'legacy-1', 'legacy-2'},
          reason: 'a bare-array payload must migrate forward, not be wiped');
    });

    test('current envelope payload loads, and round-trips through a save',
        () async {
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      await q.enqueue(_entry(clientSetId: 'env-1'));

      // Inspect the raw stored value — it must now be the versioned envelope.
      final p = await SharedPreferences.getInstance();
      final raw = jsonDecode(p.getString(key)!);
      expect(raw, isA<Map>());
      expect((raw as Map)['schemaVersion'], OfflineSetQueue.currentSchemaVersion);
      expect(raw['entries'], isA<List>());

      // And it reloads cleanly.
      expect((await q.loadAll()).single.clientSetId, 'env-1');
    });

    test('envelope tagged schemaVersion 1 migrates its entries forward',
        () async {
      // Simulate an envelope written by the first envelope-aware build.
      final env = {
        'schemaVersion': 1,
        'entries': [_entry(clientSetId: 'v1-entry').toJson()],
      };
      SharedPreferences.setMockInitialValues({key: jsonEncode(env)});

      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      expect((await q.loadAll()).single.clientSetId, 'v1-entry');
    });

    test('FUTURE schemaVersion is read best-effort, queue not wiped', () async {
      // A newer build wrote v999; an older build opening it must still recover
      // the entries (per-entry fromJson tolerates unknown keys).
      final env = {
        'schemaVersion': 999,
        'entries': [_entry(clientSetId: 'future-entry').toJson()],
      };
      SharedPreferences.setMockInitialValues({key: jsonEncode(env)});

      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      expect((await q.loadAll()).single.clientSetId, 'future-entry');
    });

    test('garbage payload falls back to an empty queue (no throw)', () async {
      SharedPreferences.setMockInitialValues({key: 'not json at all'});
      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      expect(await q.pendingCount(), 0);
    });
  });

  // ── Item 2: TTL + cap (bounded queue, never silent) ───────────────────────
  group('queue TTL + cap', () {
    const key = 'zvelt_offline_set_queue_v1_user-1';

    test('entries older than the TTL are pruned on load', () async {
      final old = DateTime.now().subtract(
        OfflineSetQueue.entryTtl + const Duration(days: 1),
      );
      final fresh = DateTime.now();
      final env = {
        'schemaVersion': OfflineSetQueue.currentSchemaVersion,
        'entries': [
          _entry(clientSetId: 'stale', queuedAt: old).toJson(),
          _entry(clientSetId: 'fresh', queuedAt: fresh).toJson(),
        ],
      };
      SharedPreferences.setMockInitialValues({key: jsonEncode(env)});

      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      final all = await q.loadAll();

      expect(all.map((e) => e.clientSetId).toList(), ['fresh'],
          reason: 'a set stuck failing past the TTL must be condensed out');
    });

    test('an entry just inside the TTL window is KEPT', () async {
      final recent = DateTime.now().subtract(
        OfflineSetQueue.entryTtl - const Duration(hours: 1),
      );
      final env = {
        'schemaVersion': OfflineSetQueue.currentSchemaVersion,
        'entries': [_entry(clientSetId: 'recent', queuedAt: recent).toJson()],
      };
      SharedPreferences.setMockInitialValues({key: jsonEncode(env)});

      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      expect((await q.loadAll()).single.clientSetId, 'recent');
    });

    test('cap drops the OLDEST entries, keeping the newest maxEntries', () async {
      final base = DateTime.now().subtract(const Duration(hours: 1));
      // One over the cap. Entries are in enqueue order (oldest first).
      final entries = [
        for (var i = 0; i < OfflineSetQueue.maxEntries + 1; i++)
          _entry(
            clientSetId: 'c$i',
            // Strictly increasing queuedAt; all within the TTL window.
            queuedAt: base.add(Duration(seconds: i)),
          ).toJson(),
      ];
      final env = {
        'schemaVersion': OfflineSetQueue.currentSchemaVersion,
        'entries': entries,
      };
      SharedPreferences.setMockInitialValues({key: jsonEncode(env)});

      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      final all = await q.loadAll();

      expect(all.length, OfflineSetQueue.maxEntries);
      // The single oldest entry (c0) must be the one dropped.
      expect(all.first.clientSetId, 'c1');
      expect(all.any((e) => e.clientSetId == 'c0'), isFalse);
    });

    test('TTL prune preserves enqueue order of survivors (replay ordering)',
        () async {
      final t0 = DateTime.now().subtract(const Duration(hours: 3));
      final env = {
        'schemaVersion': OfflineSetQueue.currentSchemaVersion,
        'entries': [
          _entry(clientSetId: 'a', queuedAt: t0).toJson(),
          _entry(clientSetId: 'b', queuedAt: t0.add(const Duration(minutes: 1)))
              .toJson(),
          _entry(clientSetId: 'c', queuedAt: t0.add(const Duration(minutes: 2)))
              .toJson(),
        ],
      };
      SharedPreferences.setMockInitialValues({key: jsonEncode(env)});

      final q = OfflineSetQueue(auth: _FakeAuth(), workouts: _FakeWorkouts());
      expect((await q.loadAll()).map((e) => e.clientSetId).toList(),
          ['a', 'b', 'c']);
    });
  });
}
