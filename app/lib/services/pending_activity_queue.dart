// Durable offline store for completed GPS sessions that could not reach
// POST /v1/activities (network down, server 5xx). Mirrors the OfflineSetQueue
// pattern: per-user SharedPreferences key, versioned envelope, TTL + cap,
// 4xx-drop / transient-backoff. Replay is driven by OfflineSyncCoordinator
// (connectivity regain / app resume / explicit refresh).
//
// A route is the one thing that cannot be re-created after the fact — losing
// it means the run never happened. So the entry carries the FULL canonical
// payload ({lat,lng,t} points included) and survives app restarts.
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '_crash_reporter.dart';
import 'activity_service.dart';
import 'auth_service.dart';

/// One queued GPS session, self-contained for replay.
class PendingActivityEntry {
  PendingActivityEntry({
    required this.clientActivityId,
    required this.mode,
    required this.routePoints,
    required this.distanceM,
    required this.durationS,
    this.calories,
    this.visibility = 'private',
    required this.startedAtIso,
    required this.endedAtIso,
    String? queuedAtIso,
    this.attempts = 0,
    this.nextAttemptAtIso,
  }) : queuedAtIso = queuedAtIso ?? DateTime.now().toUtc().toIso8601String();

  final String clientActivityId;
  final String mode; // run | bike | walk — reused for the XP award on replay
  final List<Map<String, dynamic>> routePoints; // canonical {lat,lng,t}
  final double distanceM;
  final int durationS;
  final int? calories;
  final String visibility;
  final String startedAtIso;
  final String endedAtIso;
  final String queuedAtIso;
  int attempts;
  String? nextAttemptAtIso;

  Map<String, dynamic> toJson() => {
        'clientActivityId': clientActivityId,
        'mode': mode,
        'routePoints': routePoints,
        'distanceM': distanceM,
        'durationS': durationS,
        if (calories != null) 'calories': calories,
        'visibility': visibility,
        'startedAtIso': startedAtIso,
        'endedAtIso': endedAtIso,
        'queuedAtIso': queuedAtIso,
        'attempts': attempts,
        if (nextAttemptAtIso != null) 'nextAttemptAtIso': nextAttemptAtIso,
      };

  static PendingActivityEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final id = j['clientActivityId'] as String?;
    final started = j['startedAtIso'] as String?;
    final ended = j['endedAtIso'] as String?;
    if (id == null || started == null || ended == null) return null;
    final pts = j['routePoints'];
    return PendingActivityEntry(
      clientActivityId: id,
      mode: j['mode'] as String? ?? 'run',
      routePoints: pts is List
          ? [
              for (final p in pts)
                if (p is Map) Map<String, dynamic>.from(p),
            ]
          : const [],
      distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0,
      durationS: (j['durationS'] as num?)?.toInt() ?? 0,
      calories: (j['calories'] as num?)?.toInt(),
      visibility: j['visibility'] as String? ?? 'private',
      startedAtIso: started,
      endedAtIso: ended,
      queuedAtIso: j['queuedAtIso'] as String?,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAtIso: j['nextAttemptAtIso'] as String?,
    );
  }
}

/// Result summary of a [PendingActivityQueue.flush].
class ActivityFlushResult {
  const ActivityFlushResult(
      {this.synced = 0, this.dropped = 0, this.deferred = 0});
  final int synced;
  final int dropped;
  final int deferred;
}

class PendingActivityQueue {
  PendingActivityQueue({
    AuthService? auth,
    @visibleForTesting
    Future<SavedActivity> Function(PendingActivityEntry entry)? sender,
    @visibleForTesting
    Future<void> Function(PendingActivityEntry entry, SavedActivity saved)?
        xpAwarder,
  })  : _auth = auth ?? AuthService(),
        _sender = sender,
        _xpAwarder = xpAwarder;

  final AuthService _auth;
  final Future<SavedActivity> Function(PendingActivityEntry entry)? _sender;
  final Future<void> Function(PendingActivityEntry entry, SavedActivity saved)?
      _xpAwarder;

  static const _prefsPrefix = 'zvelt_offline_activity_queue_v1';
  static const int schemaVersion = 1;

  /// Routes are heavy (a 1h run ≈ hundreds of KB of points) — cap low.
  static const int maxEntries = 20;
  static const Duration ttl = Duration(days: 14);

  // Same future-chain mutex as OfflineSetQueue — serializes enqueue/flush
  // without adding a dependency.
  Future<void> _lock = Future.value();
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _key() async {
    final id = await _auth.getCurrentUserId();
    return '${_prefsPrefix}_${id ?? 'anonymous'}';
  }

  Future<void> enqueue(PendingActivityEntry entry) => _synchronized(() async {
        final entries = await _load();
        entries.add(entry);
        // Cap: keep the NEWEST entries (a stuck queue must not eat storage).
        while (entries.length > maxEntries) {
          final dropped = entries.removeAt(0);
          debugPrint(
              '[PendingActivityQueue] dropped ${dropped.clientActivityId} (cap $maxEntries)');
        }
        await _save(entries);
      });

  Future<int> pendingCount() async => (await _load()).length;

  /// Replay queued sessions in order. Per entry:
  ///  * success → award XP best-effort (server-returned metrics) → remove;
  ///  * [ActivitySaveException] (4xx) → drop, it will never succeed;
  ///  * transient (network/5xx) → backoff + STOP (we're likely offline).
  Future<ActivityFlushResult> flush() => _synchronized(() async {
        final entries = await _load();
        if (entries.isEmpty) return const ActivityFlushResult();
        final now = DateTime.now().toUtc();
        var synced = 0, dropped = 0, deferred = 0;
        final kept = <PendingActivityEntry>[];
        var stopped = false;

        for (var i = 0; i < entries.length; i++) {
          final e = entries[i];
          if (stopped) {
            kept.add(e);
            continue;
          }
          // TTL — a two-week-old queued route is stale; drop, don't surprise.
          final queued = DateTime.tryParse(e.queuedAtIso);
          if (queued != null && now.difference(queued) > ttl) {
            dropped++;
            continue;
          }
          // Backoff window not elapsed yet.
          final next = e.nextAttemptAtIso == null
              ? null
              : DateTime.tryParse(e.nextAttemptAtIso!);
          if (next != null && now.isBefore(next)) {
            deferred++;
            kept.add(e);
            continue;
          }
          try {
            final saved = await _send(e);
            synced++;
            await _awardXp(e, saved);
          } on ActivitySaveException catch (err) {
            // Invalid payload — retrying is pointless. Drop with a breadcrumb.
            reportError(err, StackTrace.current,
                reason: 'activity-queue:drop-4xx');
            dropped++;
          } catch (_) {
            // Network / 5xx — keep with exponential backoff and stop the pass.
            e.attempts += 1;
            final delayMin =
                [1, 2, 4, 8, 16, 32, 60][e.attempts.clamp(1, 7) - 1];
            e.nextAttemptAtIso =
                now.add(Duration(minutes: delayMin)).toIso8601String();
            kept.add(e);
            deferred++;
            stopped = true;
          }
        }
        await _save(kept);
        return ActivityFlushResult(
            synced: synced, dropped: dropped, deferred: deferred);
      });

  Future<SavedActivity> _send(PendingActivityEntry e) {
    final sender = _sender;
    if (sender != null) return sender(e);
    return ActivityService().saveActivity(
      routePoints: e.routePoints,
      distanceM: e.distanceM,
      durationS: e.durationS,
      calories: e.calories,
      visibility: e.visibility,
      startedAt: DateTime.parse(e.startedAtIso),
      endedAt: DateTime.parse(e.endedAtIso),
    );
  }

  /// XP for a replayed session — best-effort: the route is already safe on the
  /// server; a lost XP award must never re-queue the activity (duplicates).
  Future<void> _awardXp(PendingActivityEntry e, SavedActivity saved) async {
    try {
      final awarder = _xpAwarder;
      if (awarder != null) return await awarder(e, saved);
      await ActivityService().completeCardio(
        mode: e.mode == 'walk' ? 'run' : e.mode,
        distanceM: (saved.distanceM ?? e.distanceM),
        durationSec: (saved.durationS ?? e.durationS).clamp(1, 86400),
        source: 'offline-replay',
      );
    } catch (err, st) {
      reportError(err, st, reason: 'activity-queue:replay-xp');
    }
  }

  // ─── storage ──────────────────────────────────────────────────────────────

  Future<List<PendingActivityEntry>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(await _key());
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return [];
      final list = decoded['entries'];
      if (list is! List) return [];
      return [
        for (final e in list)
          if (PendingActivityEntry.fromJson(e) case final entry?) entry,
      ];
    } catch (e) {
      debugPrint('[PendingActivityQueue._load] best-effort skip: $e');
      return [];
    }
  }

  Future<void> _save(List<PendingActivityEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _key();
      if (entries.isEmpty) {
        await prefs.remove(key);
        return;
      }
      await prefs.setString(
        key,
        jsonEncode({
          'schemaVersion': schemaVersion,
          'entries': [for (final e in entries) e.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('[PendingActivityQueue._save] best-effort skip: $e');
    }
  }
}
