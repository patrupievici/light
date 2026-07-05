// PendingActivityQueue — the durable offline store for GPS sessions.
//
// What matters here (and what these tests pin down):
//   1. the canonical wire payload: {lat, lng, t: EPOCH MS} — the backend
//      normalizer drops ISO timestamp strings, so a regression back to ISO
//      would silently lose server-side moving-time/pace;
//   2. replay semantics: success → XP award (server metrics) → removed;
//      4xx → dropped forever; transient → kept with backoff, pass stops.
//
// Network is avoided entirely: AuthService is faked and the queue's sender /
// xpAwarder hooks are injected.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zvelt_app/services/activity_service.dart';
import 'package:zvelt_app/services/auth_service.dart';
import 'package:zvelt_app/services/pending_activity_queue.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getCurrentUserId() async => 'user-1';
}

PendingActivityEntry _entry({
  String id = 'act_1',
  String mode = 'run',
  int attempts = 0,
  String? nextAttemptAtIso,
  String? queuedAtIso,
}) =>
    PendingActivityEntry(
      clientActivityId: id,
      mode: mode,
      routePoints: const [
        {'lat': 44.4268, 'lng': 26.1025, 't': 1700000000000},
        {'lat': 44.4270, 'lng': 26.1030, 't': 1700000005000},
      ],
      distanceM: 1234.5,
      durationS: 600,
      calories: 88,
      startedAtIso: '2026-07-05T10:00:00.000Z',
      endedAtIso: '2026-07-05T10:10:00.000Z',
      attempts: attempts,
      nextAttemptAtIso: nextAttemptAtIso,
      queuedAtIso: queuedAtIso,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ActivityService.routePointsFrom — canonical payload', () {
    test('emits {lat, lng, t: epoch ms} for each point', () {
      final pts = [const LatLng(44.4268, 26.1025), const LatLng(44.4270, 26.1030)];
      final ts = [
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
        DateTime.fromMillisecondsSinceEpoch(1700000005000, isUtc: true),
      ];

      final out = ActivityService.routePointsFrom(pts, ts);

      expect(out, hasLength(2));
      expect(out[0], {'lat': 44.4268, 'lng': 26.1025, 't': 1700000000000});
      expect(out[1]['t'], 1700000005000);
      // Regression guard: 't' must be an int (epoch ms), never an ISO string —
      // the backend normalizer nulls string timestamps.
      expect(out.every((p) => p['t'] is int), isTrue);
      expect(out.every((p) => !p.containsKey('ts')), isTrue);
    });

    test('omits t when timestamps run short (never crashes on mismatch)', () {
      final pts = [const LatLng(1, 2), const LatLng(3, 4)];
      final ts = [DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true)];

      final out = ActivityService.routePointsFrom(pts, ts);

      expect(out[0].containsKey('t'), isTrue);
      expect(out[1].containsKey('t'), isFalse);
    });
  });

  group('PendingActivityEntry — JSON roundtrip', () {
    test('toJson/fromJson preserves the full payload', () {
      final e = _entry(attempts: 3, nextAttemptAtIso: '2026-07-05T11:00:00.000Z');

      final back = PendingActivityEntry.fromJson(e.toJson());

      expect(back, isNotNull);
      expect(back!.clientActivityId, 'act_1');
      expect(back.mode, 'run');
      expect(back.routePoints, e.routePoints);
      expect(back.distanceM, 1234.5);
      expect(back.durationS, 600);
      expect(back.calories, 88);
      expect(back.visibility, 'private');
      expect(back.startedAtIso, '2026-07-05T10:00:00.000Z');
      expect(back.endedAtIso, '2026-07-05T10:10:00.000Z');
      expect(back.attempts, 3);
      expect(back.nextAttemptAtIso, '2026-07-05T11:00:00.000Z');
    });

    test('fromJson rejects malformed rows instead of crashing', () {
      expect(PendingActivityEntry.fromJson(null), isNull);
      expect(PendingActivityEntry.fromJson('junk'), isNull);
      expect(PendingActivityEntry.fromJson({'mode': 'run'}), isNull);
    });
  });

  group('flush', () {
    test('success → sends payload, awards XP with server metrics, removes entry',
        () async {
      final sent = <PendingActivityEntry>[];
      final xp = <(String mode, double dist, int dur)>[];
      final queue = PendingActivityQueue(
        auth: _FakeAuth(),
        sender: (e) async {
          sent.add(e);
          return const SavedActivity(
              id: 'srv-1', distanceM: 1500, durationS: 620, recomputed: true);
        },
        xpAwarder: (e, saved) async {
          xp.add((e.mode, saved.distanceM!, saved.durationS!));
        },
      );
      await queue.enqueue(_entry());

      final result = await queue.flush();

      expect(result.synced, 1);
      expect(result.dropped, 0);
      expect(sent.single.clientActivityId, 'act_1');
      // XP is awarded on SERVER-recomputed metrics, not the local estimate.
      expect(xp.single, ('run', 1500.0, 620));
      expect(await queue.pendingCount(), 0);
    });

    test('4xx → dropped permanently (no retry of an invalid payload)', () async {
      final queue = PendingActivityQueue(
        auth: _FakeAuth(),
        sender: (_) async => throw ActivitySaveException(422, 'bad payload'),
        xpAwarder: (_, __) async => fail('XP must not be awarded on drop'),
      );
      await queue.enqueue(_entry());

      final result = await queue.flush();

      expect(result.dropped, 1);
      expect(result.synced, 0);
      expect(await queue.pendingCount(), 0);
    });

    test('transient failure → kept with backoff; next flush defers', () async {
      var calls = 0;
      final queue = PendingActivityQueue(
        auth: _FakeAuth(),
        sender: (_) async {
          calls++;
          throw Exception('network down');
        },
      );
      await queue.enqueue(_entry());

      final first = await queue.flush();
      expect(first.deferred, 1);
      expect(first.synced, 0);
      expect(await queue.pendingCount(), 1); // route survives

      // Immediately after, the backoff window has not elapsed — no re-send.
      final second = await queue.flush();
      expect(second.deferred, 1);
      expect(calls, 1);
    });

    test('transient failure stops the pass — later entries are not attempted',
        () async {
      final attempted = <String>[];
      final queue = PendingActivityQueue(
        auth: _FakeAuth(),
        sender: (e) async {
          attempted.add(e.clientActivityId);
          throw Exception('offline');
        },
      );
      await queue.enqueue(_entry(id: 'act_1'));
      await queue.enqueue(_entry(id: 'act_2'));

      await queue.flush();

      expect(attempted, ['act_1']); // act_2 untouched — we're offline
      expect(await queue.pendingCount(), 2);
    });

    test('entries older than the 14-day TTL are dropped', () async {
      final queue = PendingActivityQueue(
        auth: _FakeAuth(),
        sender: (_) async => fail('stale entry must not be sent'),
      );
      final stale = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 15))
          .toIso8601String();
      await queue.enqueue(_entry(queuedAtIso: stale));

      final result = await queue.flush();

      expect(result.dropped, 1);
      expect(await queue.pendingCount(), 0);
    });

    test('a failed XP award does NOT re-queue the activity (no duplicates)',
        () async {
      final queue = PendingActivityQueue(
        auth: _FakeAuth(),
        sender: (_) async => const SavedActivity(id: 'srv-1'),
        xpAwarder: (_, __) async => throw Exception('xp endpoint down'),
      );
      await queue.enqueue(_entry());

      final result = await queue.flush();

      // The activity reached the server; losing the XP award must not cause a
      // replay that would duplicate the activity.
      expect(result.synced, 1);
      expect(await queue.pendingCount(), 0);
    });
  });
}
