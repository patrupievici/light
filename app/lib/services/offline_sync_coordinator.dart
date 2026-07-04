import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_bootstrap_queue.dart';
import 'offline_set_queue.dart';
import 'settings_store.dart';

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
  final OfflineBootstrapQueue _bootstrapQueue = OfflineBootstrapQueue();
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
      unawaited(_flushIfAutoAllowed());
    }
  }

  /// Resume-triggered auto-flush, gated by the Cloud Sync settings (reads the
  /// current connectivity since a lifecycle event carries none).
  Future<void> _flushIfAutoAllowed() async {
    List<ConnectivityResult> results;
    try {
      results = await _connectivity.checkConnectivity();
    } catch (_) {
      results = const [ConnectivityResult.wifi]; // assume unrestricted on error
    }
    if (await _autoSyncAllowed(results)) await _safeFlush();
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

  /// Enqueue a pending workout-create (offline "start workout"). Replayed BEFORE
  /// its exercises and sets on reconnect (see [_safeFlush]).
  Future<void> enqueueBootstrapWorkout({
    required String workoutId,
    String? label,
  }) async {
    await _bootstrapQueue.enqueueWorkout(workoutId: workoutId, label: label);
    await _refreshCount();
  }

  /// Enqueue a pending exercise-create (offline "add exercise"). Replayed after
  /// its parent workout-create and before any set that targets it.
  Future<void> enqueueBootstrapExercise({
    required String workoutId,
    required String exerciseId,
    required String weId,
    int? position,
  }) async {
    await _bootstrapQueue.enqueueExercise(
      workoutId: workoutId,
      exerciseId: exerciseId,
      weId: weId,
      position: position,
    );
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

  bool _isCellular(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.mobile) &&
      !results.contains(ConnectivityResult.wifi) &&
      !results.contains(ConnectivityResult.ethernet);

  /// Honors the user's Cloud Sync settings for AUTOMATIC flushes only (manual
  /// "Sync now" always flushes). Auto-sync OFF → never auto-flush; "Sync on
  /// cellular" OFF → skip auto-flush while on a cellular-only connection.
  /// Defaults are ON, so the toggles only ever restrict behaviour.
  Future<bool> _autoSyncAllowed(List<ConnectivityResult> results) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final auto = prefs.getBool(SettingsKeys.cloudAuto) ?? true;
      if (!auto) return false;
      final cellularOk = prefs.getBool(SettingsKeys.cloudCellular) ?? true;
      if (!cellularOk && _isCellular(results)) return false;
      return true;
    } catch (_) {
      return true; // best-effort: a prefs read failure must not strand the queue
    }
  }

  Future<void> _onChange(List<ConnectivityResult> results) async {
    final online = _isOnline(results);
    final transitionedOnline = online && !_wasOnline;
    _wasOnline = online;
    if (transitionedOnline && await _autoSyncAllowed(results)) {
      await _safeFlush();
    } else {
      await _refreshCount();
    }
  }

  Future<void> _safeFlush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      // Bootstrap (workout-create → exercise-create) drains FIRST so the
      // skeleton a set needs exists before the set is sent.
      await _bootstrapQueue.flush();
      // Only drain sets once EVERY create has landed. If any create is still
      // pending (still offline / in backoff), a set flushed now would POST
      // against a not-yet-created exercise, 404, and be dropped as an
      // un-retryable 4xx — silent data loss. Skip the set flush this round;
      // it retries on the next reconnect/foreground once the creates clear.
      if (await _bootstrapQueue.pendingCount() == 0) {
        await _queue.flush();
      }
    } catch (_) {
      // network/server errors are kept in each queue by its own flush().
    } finally {
      _flushing = false;
      await _refreshCount();
    }
  }

  Future<void> _refreshCount() async {
    // Surface total outstanding work (creates + sets) on the sync indicator.
    final n =
        (await _bootstrapQueue.pendingCount()) + (await _queue.pendingCount());
    if (pendingCount.value != n) pendingCount.value = n;
  }
}
