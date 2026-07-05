import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'offline_set_queue.dart';
import 'pending_activity_queue.dart';

/// App-wide bridge between connectivity changes and the offline set queue.
/// UI subscribes to [pendingCount]; transitions to online auto-flush.
///
/// Three triggers drain the queue, all funnelled through the single
/// re-entrancy-guarded [_safeFlush]:
///   1. connectivity regained (offline → online) — [_onChange];
///   2. app brought back to the foreground — [didChangeAppLifecycleState];
///   3. an explicit foreground refresh — [refreshPending].
/// Because every path shares the [_flushing] guard, an app-resume that races a
/// connectivity-regain (or main.dart's own resume hook) coalesces into one
/// flush rather than hammering the backend in parallel.
class OfflineSyncCoordinator with WidgetsBindingObserver {
  OfflineSyncCoordinator._();
  static final OfflineSyncCoordinator instance = OfflineSyncCoordinator._();

  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  final OfflineSetQueue _queue = OfflineSetQueue();
  final PendingActivityQueue _activityQueue = PendingActivityQueue();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOnline = true;
  bool _flushing = false;
  bool _started = false;
  bool _lifecycleHooked = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _refreshCount();
    try {
      _wasOnline = _isOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      _wasOnline = true;
    }
    _sub = _connectivity.onConnectivityChanged.listen(_onChange);
    // Self-wire the app-resume flush so a queued set drains on foreground even
    // without a connectivity transition (e.g. the radio never dropped but a
    // request failed while backgrounded). Guarded against double-registration;
    // shares _safeFlush with main.dart's resume hook so the two coalesce.
    final binding = WidgetsBinding.instance;
    if (!_lifecycleHooked) {
      binding.addObserver(this);
      _lifecycleHooked = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Foreground regain — attempt to drain anything queued while backgrounded.
    // Fire-and-forget + guarded so a teardown/error can never bubble into the
    // framework's lifecycle dispatch.
    if (state == AppLifecycleState.resumed && _started) {
      unawaited(_safeFlush());
    }
  }

  /// Enqueue + bump count. Use from screens that detect a failed set mutation
  /// (add, edit, or delete — the entry carries its own [PendingSetEntry.op]).
  ///
  /// Replay ordering — a set's `add` must flush before any `update`/`delete` of
  /// the SAME set — is enforced by [OfflineSetQueue.flush], which iterates in
  /// enqueue order and holds a child op back (deferred) while its parent add is
  /// still pending. Callers therefore only need to enqueue in the order the
  /// user performed the mutations (which is the natural call order).
  Future<void> enqueue(PendingSetEntry entry) async {
    await _queue.enqueue(entry);
    await _refreshCount();
  }

  /// Durable-store a completed GPS session whose backend save failed
  /// (offline / 5xx). Replays through the same flush triggers as sets.
  Future<void> enqueueActivity(PendingActivityEntry entry) async {
    await _activityQueue.enqueue(entry);
    await _refreshCount();
  }

  /// Force a flush attempt (used by foreground screens that need fresh state).
  Future<void> refreshPending({bool flush = false}) async {
    if (flush) {
      await _safeFlush();
    } else {
      await _refreshCount();
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    if (_lifecycleHooked) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleHooked = false;
    }
    _started = false;
  }

  // ─── internals ────────────────────────────────────────────────────────────

  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> _onChange(List<ConnectivityResult> results) async {
    final online = _isOnline(results);
    final transitionedOnline = online && !_wasOnline;
    _wasOnline = online;
    if (transitionedOnline) {
      await _safeFlush();
    } else {
      await _refreshCount();
    }
  }

  Future<void> _safeFlush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _queue.flush();
    } catch (_) {
      // network/server errors are kept in the queue by flush() itself.
    }
    try {
      await _activityQueue.flush();
    } catch (_) {
      // same contract: transient failures stay queued with backoff.
    }
    _flushing = false;
    await _refreshCount();
  }

  Future<void> _refreshCount() async {
    final sets = await _queue.pendingCount();
    final activities = await _activityQueue.pendingCount();
    final n = sets + activities;
    if (pendingCount.value != n) pendingCount.value = n;
  }
}
