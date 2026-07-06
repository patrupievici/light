import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../theme/zvelt_tokens.dart';
import '../../l10n/app_strings.dart';
import '../../models/exercise_load_policy.dart';
import '../../services/health_service.dart';
import '../../services/muscle_recovery_service.dart';
import '../../services/offline_set_queue.dart';
import '../../services/offline_sync_coordinator.dart';
import '../../services/rest_interval_store.dart';
import '../../services/watch_connectivity_service.dart';
import '../../services/workout_service.dart';
import '../../widgets/zvelt_secondary_button.dart';
import '../../services/routine_service.dart';
import '../../widgets/exercise_gif_dialog.dart';
import '../../widgets/plate_calculator.dart';
import '../../widgets/set_log_dialog.dart';
import '../../widgets/sync_status_chip.dart';
import '../../widgets/weight_jump_note_sheet.dart';
import 'exercise_library_screen.dart';
import 'xp_complete_screen.dart';

/// Tracker: exerciții, seturi (kg/reps/RPE), timer live, Complete → XP screen.
class WorkoutTrackerScreen extends StatefulWidget {
  const WorkoutTrackerScreen({
    super.key,
    required this.workoutId,
    this.onComplete,
  });

  final String workoutId;
  final VoidCallback? onComplete;

  @override
  State<WorkoutTrackerScreen> createState() => _WorkoutTrackerScreenState();
}

class _WorkoutTrackerScreenState extends State<WorkoutTrackerScreen> {
  final WorkoutService _service = WorkoutService();
  final RoutineService _routineService = RoutineService();
  WorkoutDto? _workout;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  /// Drives ONLY the appbar clock. Ticking this every second via
  /// [ValueListenableBuilder] keeps the per-second rebuild scoped to the
  /// timer text — the exercise list is no longer rebuilt once a second.
  final ValueNotifier<Duration> _elapsed =
      ValueNotifier<Duration>(Duration.zero);

  /// Drives the prescribed rest-timer countdown banner only. Null = no rest
  /// countdown is currently running (the common case: between sets the user is
  /// either not resting or no prescription exists). Holding the live state in a
  /// [ValueNotifier] keeps the per-second tick scoped to the banner — the
  /// exercise list is never rebuilt by the countdown. Additive UI: this is
  /// seeded only after a successful set log and never gates the log/patch flow.
  final ValueNotifier<RestCountdown?> _restCountdown =
      ValueNotifier<RestCountdown?>(null);

  /// Independent 1 Hz ticker for [_restCountdown]; started on demand and torn
  /// down once the countdown finishes/skips so it never runs idle.
  Timer? _restTimer;

  /// Wall-clock instant the user last marked any set complete, keyed by the
  /// `workoutExercise.id` that set belongs to. Used to derive rest periods
  /// for the on-device analytics store — `now − _lastSetEndedAt[weId]` is the
  /// rest preceding the *current* set logged for that exercise. Cleared on
  /// workout exit (state disposal). See [RestIntervalStore].
  final Map<String, DateTime> _lastSetEndedAt = <String, DateTime>{};

  /// Snapshot the rest baseline immediately after a successful set log so
  /// the *next* set on the same exercise can derive its rest period.
  /// Called from the two set-completion paths (`_logPendingSet`,
  /// `_saveSetInline`).
  // ── PR detection (brief §8/§15) ────────────────────────────────────────────
  /// Historical best e1RM per exercise, seeded once from GET /ranks/me and then
  /// raised in-session as the user beats it. Epley e1RM, WORK sets, reps 1-12.
  final Map<String, double> _bestE1rm = {};
  final Set<String> _prSetIds = {};
  bool _prBaselineLoaded = false;

  // ── Auto-progression (brief §8.3) — suggested next load per exercise ────────
  final Map<String, ProgressionSuggestion> _progression = {};

  /// Best-effort: fetch the suggested next working load for each exercise in the
  /// workout so the card can show "Next: 82.5kg (+2.5)" with the why. One call
  /// per exercise, fired after the workout loads; failures just skip the hint.
  Future<void> _loadProgression(WorkoutDto w) async {
    final seen = <String>{};
    for (final we in w.exercises) {
      final id = we.exerciseId;
      if (id.isEmpty || !seen.add(id)) continue;
      final reps =
          int.tryParse(we.repRangeHint?.split(RegExp(r'\D+')).firstWhere(
                        (s) => s.isNotEmpty,
                        orElse: () => '',
                      ) ??
                  '') ??
              8;
      final s = await _service.getProgression(id, reps: reps);
      if (!mounted) return;
      if (s != null) setState(() => _progression[id] = s);
    }
  }

  Future<void> _loadPrBaseline() async {
    try {
      final ranks = await _service.getMyRanks();
      if (!mounted) return;
      for (final r in ranks) {
        _bestE1rm[r.exerciseId] = r.bestE1rmKg;
      }
      _prBaselineLoaded = true;
    } catch (_) {/* no baseline → skip PR detection rather than over-flag */}
  }

  /// Flags a personal record when a completed WORK set's Epley e1RM beats the
  /// historical (and in-session) best for that exercise. Celebrates + marks the
  /// set so the row shows a trophy. No-op until the baseline actually loaded, so
  /// a failed ranks fetch never fabricates a PR on every first set.
  void _maybeFlagPr({
    required String exerciseId,
    required double weightKg,
    required int reps,
    required String tag,
    required String setId,
  }) {
    if (!_prBaselineLoaded) return;
    if (tag != 'WORK' || reps < 1 || reps > 12 || weightKg <= 0) return;
    final e1rm = weightKg * (1 + reps / 30);
    final best = _bestE1rm[exerciseId] ?? 0;
    if (e1rm <= best + 0.05) return;
    _bestE1rm[exerciseId] = e1rm;
    if (!mounted) return;
    setState(() => _prSetIds.add(setId));
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text('🏆 New PR — e1RM ${e1rm.toStringAsFixed(1)} kg'),
      backgroundColor: ZveltTokens.success,
      duration: const Duration(seconds: 3),
    ));
  }

  bool _isTransientSetFailure(Object e) {
    if (e is WorkoutApiException) {
      return e.statusCode == 408 || e.statusCode == 429 || e.statusCode >= 500;
    }
    return true;
  }

  void _showSetSaveError(Object e) {
    if (!mounted) return;
    final message = e.toString().replaceFirst('Exception: ', '').trim();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.isEmpty ? 'Could not log set' : message),
        backgroundColor: ZveltTokens.error,
      ),
    );
  }

  WorkoutSetDto _completedSetSnapshot(
    WorkoutSetDto set, {
    required double weightKg,
    required int reps,
    double? rpe,
  }) {
    return WorkoutSetDto(
      id: set.id,
      setIndex: set.setIndex,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe,
      tag: set.tag,
      isCompleted: true,
    );
  }

  Future<void> _applyCompletedSetLocally({
    required WorkoutExerciseDto we,
    required WorkoutSetDto set,
    required double weightKg,
    required int reps,
    WorkoutSetDto? serverSet,
  }) async {
    final completed = serverSet ??
        _completedSetSnapshot(set,
            weightKg: weightKg, reps: reps, rpe: set.rpe);
    await _recordSetCompletion(we: we, setId: completed.id);
    if (!mounted) return;
    _patchWorkoutSets(we.id, (sets) {
      final idx = sets.indexWhere((s) => s.id == completed.id);
      if (idx >= 0) sets[idx] = completed;
      return sets;
    });
    _maybeFlagPr(
      exerciseId: we.exerciseId,
      weightKg: weightKg,
      reps: reps,
      tag: completed.tag,
      setId: completed.id,
    );
  }

  Future<void> _recordSetCompletion({
    required WorkoutExerciseDto we,
    required String setId,
  }) async {
    final now = DateTime.now();
    final prev = _lastSetEndedAt[we.id];
    _lastSetEndedAt[we.id] = now;
    // Start the prescribed rest countdown for the *upcoming* rest, seeded from
    // the exercise prescription. No prescription → no countdown (P2 contract).
    // Done before the early-return so the first set of an exercise still kicks
    // off a rest timer for the gap before its second set.
    _startRestCountdown(we);
    if (prev == null) {
      return; // First completed set on this exercise — no rest yet.
    }
    final rest = now.difference(prev).inSeconds;
    await RestIntervalStore.instance.logRestInterval(
      exerciseId: we.exerciseId,
      exerciseName: we.exercise.name,
      workoutId: widget.workoutId,
      setId: setId,
      restSeconds: rest,
      endedAt: now,
    );
  }

  /// Seed and start the unobtrusive rest countdown from [we]'s prescription
  /// (`restSecondsDefault`). A no-op when there is no positive prescription, so
  /// exercises without planned rest never show a timer. Replaces any countdown
  /// already running (logging a new set restarts the clock).
  void _startRestCountdown(WorkoutExerciseDto we) {
    final prescribed = we.restSecondsDefault ?? 0;
    if (prescribed <= 0) {
      _stopRestCountdown();
      return;
    }
    _restCountdown.value = RestCountdown(
      exerciseName: we.exercise.name,
      prescribedSeconds: prescribed,
      remainingSeconds: prescribed,
    );
    _armRestTicker();
  }

  /// Skip the rest: clear the banner immediately. UI-only — the actual rested
  /// duration is still derived from wall-clock at the next set log, so skipping
  /// the visual timer never falsifies the recorded adherence.
  void _skipRestCountdown() => _stopRestCountdown();

  /// Extend the running countdown by [extraSeconds] (capped to the rest-store's
  /// plausible-rest ceiling). No-op when no countdown is active.
  void _extendRestCountdown([int extraSeconds = 15]) {
    final c = _restCountdown.value;
    if (c == null) return;
    final extended = (c.remainingSeconds + extraSeconds).clamp(0, 30 * 60);
    _restCountdown.value = c.copyWith(remainingSeconds: extended);
    // Re-arm the ticker if it had already drained to zero.
    if (_restTimer == null && extended > 0) _armRestTicker();
  }

  /// (Re)start the single 1 Hz ticker against whatever [_restCountdown]
  /// currently holds. Cancels any existing ticker first so there is only ever
  /// one. When the countdown drains to zero it freezes at "0:00" and the ticker
  /// stops (the next set log or an extend re-arms it).
  void _armRestTicker() {
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final c = _restCountdown.value;
      if (c == null) {
        _stopRestCountdown();
        return;
      }
      final next = c.remainingSeconds - 1;
      if (next <= 0) {
        // Hold at zero for a beat so the user sees "rest over" rather than the
        // banner vanishing mid-glance; the next set log replaces it anyway.
        _restCountdown.value = c.copyWith(remainingSeconds: 0);
        _restTimer?.cancel();
        _restTimer = null;
      } else {
        _restCountdown.value = c.copyWith(remainingSeconds: next);
      }
    });
  }

  void _stopRestCountdown() {
    _restTimer?.cancel();
    _restTimer = null;
    _restCountdown.value = null;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrBaseline();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final w = _workout;
      if (w != null) {
        // Update only the clock notifier — no setState, so the exercise
        // ListView is not rebuilt every second.
        _elapsed.value = DateTime.now().difference(w.startedAt);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    _elapsed.dispose();
    _restCountdown.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final w = await _service.getWorkout(widget.workoutId);
      if (!mounted) return;
      _elapsed.value = DateTime.now().difference(w.startedAt);
      setState(() {
        _workout = w;
        _loading = false;
      });
      WatchConnectivityService.instance.sendWorkoutState(w).ignore();
      _loadProgression(w);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Rebuild [_workout] in place with [weId]'s set list transformed by
  /// [transform], then `setState` locally and refresh watch state — avoids the
  /// full GET + loading-spinner round-trip that [_load] performs. The list
  /// shape produced here mirrors what [_load] would yield (sets sorted by
  /// `setIndex`, exercise/workout structure unchanged).
  void _patchWorkoutSets(
    String weId,
    List<WorkoutSetDto> Function(List<WorkoutSetDto> sets) transform,
  ) {
    final current = _workout;
    if (current == null) return;
    final exercises = current.exercises.map((we) {
      if (we.id != weId) return we;
      final sets = transform([...we.sets])
        ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
      return WorkoutExerciseDto(
        id: we.id,
        exerciseId: we.exerciseId,
        position: we.position,
        exercise: we.exercise,
        sets: sets,
        repRangeHint: we.repRangeHint,
        restSecondsDefault: we.restSecondsDefault,
      );
    }).toList();
    final patched = WorkoutDto(
      id: current.id,
      status: current.status,
      startedAt: current.startedAt,
      endedAt: current.endedAt,
      exercises: exercises,
    );
    if (!mounted) return;
    setState(() => _workout = patched);
    WatchConnectivityService.instance.sendWorkoutState(patched).ignore();
  }

  Future<void> _addExercise() async {
    try {
      final chosen = await Navigator.of(context).push<ExerciseDto>(
        MaterialPageRoute(
          builder: (_) => const ExerciseLibraryScreen(selectionMode: true),
        ),
      );
      if (chosen == null || !mounted || _workout == null) return;
      await _service.addExercise(widget.workoutId, chosen.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: ZveltTokens.error,
        ),
      );
    }
  }

  Future<void> _addSet(WorkoutExerciseDto we) async {
    final vals =
        await _showSetDialog(exercise: we.exercise, allowTagSelection: true);
    if (vals == null || !mounted) return;
    final tag = vals.$4;
    // Same client-side UUID for the POST and any later offline-queue replay, so
    // the server dedupes on `clientSetId` rather than creating duplicate sets.
    final clientSetId = const Uuid().v4();
    // Anti-cheat retry loop: a >2× weight jump vs the recent personal max is
    // rejected until a justification note is attached. Each pass re-sends with
    // whatever note the user supplied; the note also rides any offline enqueue.
    String? note;
    while (true) {
      try {
        final added = await _service.addSet(
          widget.workoutId,
          we.id,
          weightKg: vals.$1,
          reps: vals.$2,
          rpe: vals.$3,
          tag: tag,
          clientSetId: clientSetId,
          note: note,
        );
        if (!mounted) return;
        _patchWorkoutSets(we.id, (sets) {
          // Idempotent replay can return an existing row — replace by id if
          // present, otherwise append the freshly created set.
          final idx = sets.indexWhere((s) => s.id == added.id);
          if (idx >= 0) {
            sets[idx] = added;
          } else {
            sets.add(added);
          }
          return sets;
        });
        _maybeFlagPr(
          exerciseId: we.exerciseId,
          weightKg: vals.$1,
          reps: vals.$2,
          tag: tag,
          setId: added.id,
        );
        return;
      } on WeightJumpNoteRequiredException catch (ex) {
        if (!mounted) return;
        final entered =
            await showWeightJumpNoteSheet(context, message: ex.message);
        if (entered == null) return; // user cancelled → set is NOT logged
        note = entered;
        // loop again, now with the note attached
      } catch (e) {
        if (!mounted) return;
        if (!_isTransientSetFailure(e)) {
          _showSetSaveError(e);
          return;
        }
        // Offline-first: enqueue an ADD op instead of dropping the set. The
        // coordinator's connectivity listener flushes on reconnect; the server
        // dedupes on clientSetId. Any note the user gave rides along.
        await _enqueueOfflineSet(
          PendingSetEntry.add(
            workoutId: widget.workoutId,
            weId: we.id,
            weightKg: vals.$1,
            reps: vals.$2,
            rpe: vals.$3,
            tag: tag,
            clientSetId: clientSetId,
            note: note,
          ),
        );
        return;
      }
    }
  }

  /// Offline fallback shared by the set-mutation paths: persist [entry] to the
  /// existing [OfflineSetQueue] (via [OfflineSyncCoordinator]) and tell the user
  /// it will sync on reconnect — mirrors `quick_launch_sheet.dart`. The entry's
  /// own [PendingSetEntry.op] (add/update) decides how it replays, so an offline
  /// EDIT patches the existing set rather than creating a duplicate ADD.
  Future<void> _enqueueOfflineSet(PendingSetEntry entry) async {
    await OfflineSyncCoordinator.instance.enqueue(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved offline — will sync when back online.'),
        backgroundColor: ZveltTokens.warn,
      ),
    );
  }

  /// Tap-to-retry from the offline-sync indicator: force a flush of the queued
  /// set mutations. Render + a flush call only — does not touch the log/patch
  /// flow. The coordinator keeps anything that still fails in the queue (with
  /// backoff), so the indicator's [ValueListenableBuilder] just re-hides or
  /// updates its count once `pendingCount` settles.
  Future<void> _retryOfflineSync() async {
    await OfflineSyncCoordinator.instance.refreshPending(flush: true);
  }

  Future<void> _logPendingSet(WorkoutExerciseDto we, WorkoutSetDto set) async {
    final mode = setLogModeForExercise(we.exercise);
    final defaultLoad = switch (mode) {
      SetLogMode.timeSeconds => set.weightKg >= 5 ? set.weightKg : 45.0,
      SetLogMode.bodyweightReps => 0.0,
      SetLogMode.weighted => set.weightKg > 0 ? set.weightKg : 20.0,
    };
    final vals = await _showSetDialog(
      exercise: we.exercise,
      initialWeight: defaultLoad,
      initialReps: set.reps.clamp(1, 50),
      title: AppStrings.logSet,
    );
    if (vals == null || !mounted) return;
    // Anti-cheat retry loop: a >2× jump vs the prior weight needs a note.
    String? note;
    while (true) {
      try {
        final updated = await _service.updateSet(
          widget.workoutId,
          we.id,
          set.id,
          weightKg: vals.$1,
          reps: vals.$2,
          rpe: vals.$3,
          isCompleted: true,
          note: note,
        );
        await _applyCompletedSetLocally(
          we: we,
          set: set,
          weightKg: vals.$1,
          reps: vals.$2,
          serverSet: updated,
        );
        return;
      } on WeightJumpNoteRequiredException catch (ex) {
        if (!mounted) return;
        final entered =
            await showWeightJumpNoteSheet(context, message: ex.message);
        if (entered == null) return; // user cancelled → set is NOT changed
        note = entered;
      } catch (e) {
        if (!mounted) return;
        if (!_isTransientSetFailure(e)) {
          _showSetSaveError(e);
          return;
        }
        // Offline-first: enqueue an UPDATE op (not a fresh ADD) so the existing
        // set row is patched on reconnect instead of being duplicated.
        await _enqueueOfflineSet(
          PendingSetEntry.update(
            workoutId: widget.workoutId,
            weId: we.id,
            setId: set.id,
            clientSetId: const Uuid().v4(),
            weightKg: vals.$1,
            reps: vals.$2,
            rpe: vals.$3,
            note: note,
          ),
        );
        await _applyCompletedSetLocally(
          we: we,
          set: set,
          weightKg: vals.$1,
          reps: vals.$2,
        );
        return;
      }
    }
  }

  Future<void> _saveSetInline(
    WorkoutExerciseDto we,
    WorkoutSetDto set, {
    required double weightKg,
    required int reps,
  }) async {
    // Anti-cheat retry loop: a >2× jump vs the prior weight needs a note.
    String? note;
    while (true) {
      try {
        final updated = await _service.updateSet(
          widget.workoutId,
          we.id,
          set.id,
          weightKg: weightKg,
          reps: reps,
          rpe: set.rpe,
          isCompleted: true,
          note: note,
        );
        await _applyCompletedSetLocally(
          we: we,
          set: set,
          weightKg: weightKg,
          reps: reps,
          serverSet: updated,
        );
        return;
      } on WeightJumpNoteRequiredException catch (ex) {
        if (!mounted) return;
        final entered =
            await showWeightJumpNoteSheet(context, message: ex.message);
        if (entered == null) return; // user cancelled → set is NOT changed
        note = entered;
      } catch (e) {
        if (!mounted) return;
        if (!_isTransientSetFailure(e)) {
          _showSetSaveError(e);
          return;
        }
        // Offline-first: enqueue an UPDATE op targeting this set so reconnect
        // patches the existing row instead of creating a duplicate ADD.
        await _enqueueOfflineSet(
          PendingSetEntry.update(
            workoutId: widget.workoutId,
            weId: we.id,
            setId: set.id,
            clientSetId: const Uuid().v4(),
            weightKg: weightKg,
            reps: reps,
            rpe: set.rpe,
            note: note,
          ),
        );
        await _applyCompletedSetLocally(
          we: we,
          set: set,
          weightKg: weightKg,
          reps: reps,
        );
        return;
      }
    }
  }

  Future<(double, int, double?, String)?> _showSetDialog({
    required ExerciseDto exercise,
    double initialWeight = 20,
    int initialReps = 8,
    String title = 'Log set',
    int maxReps = 50,
    bool allowTagSelection = false,
  }) {
    return showDialog<(double, int, double?, String)?>(
      context: context,
      builder: (ctx) => SetLogDialog(
        exercise: exercise,
        initialWeight: initialWeight,
        initialReps: initialReps,
        maxReps: maxReps,
        title: title,
        allowTagSelection: allowTagSelection,
        // Hold time is stored in the weightKg slot for time-mode exercises, so
        // must stay within `kSetWeightMaxKg` (500) to satisfy service-side bounds.
        timeMaxSeconds: kSetWeightMaxKg,
        timeDivisions: 99,
        holdInitGuardMax: kSetWeightMaxKg,
      ),
    );
  }

  /// Save the current workout's exercises as a reusable routine (mockup 4).
  Future<void> _saveAsRoutine() async {
    final w = _workout;
    if (w == null || w.exercises.isEmpty) return;
    final controller = TextEditingController(text: 'My Routine');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: const Text('Save as routine'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Routine name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final exercises = w.exercises.map((we) {
      final reps = we.sets.isNotEmpty
          ? we.sets.first.reps
          : int.tryParse(we.repRangeHint ?? '');
      return RoutineExercise(
        name: we.exercise.name,
        exerciseId: we.exerciseId,
        sets: we.sets.isNotEmpty ? we.sets.length : null,
        reps: reps,
        restSeconds: we.restSecondsDefault,
      );
    }).toList();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _routineService.createRoutine(
          name: name.trim(), exercises: exercises);
      messenger.showSnackBar(const SnackBar(
        content: Text('Saved as routine'),
        backgroundColor: ZveltTokens.success,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    }
  }

  Future<void> _complete() async {
    try {
      final result = await _service.completeWorkout(widget.workoutId);
      await MuscleRecoveryService().invalidateCache();
      HealthService.instance.writeWorkoutToHealth(result.workout).ignore();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => XpCompleteScreen(
            workoutId: widget.workoutId,
            xpGain: result.xpGain,
            gameXp: result.gameXp,
            onDone: () => widget.onComplete?.call(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()), backgroundColor: ZveltTokens.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _workout == null) {
      return Scaffold(
        backgroundColor: ZveltTokens.bg,
        body: const Center(
            child: CircularProgressIndicator(color: ZveltTokens.info)),
      );
    }
    if (_error != null && _workout == null) {
      return Scaffold(
        backgroundColor: ZveltTokens.bg,
        appBar: AppBar(title: const Text('Workout')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  style: const TextStyle(color: ZveltTokens.error),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final w = _workout!;
    // One extra trailing item hosts the "Add exercise" button (kept inside the
    // scroll view exactly as before).
    final itemCount = w.exercises.length + 1;

    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: const Text('Workout'),
        leading: IconButton(
          tooltip: AppStrings.discardWorkout,
          icon: const Icon(AppIcons.cross_small),
          onPressed: () => _showExitConfirm(),
        ),
        actions: [
          IconButton(
            tooltip: 'Save as routine',
            icon: const Icon(AppIcons.bookmark, size: 20),
            onPressed: _saveAsRoutine,
          ),
          // Offline-sync indicator: hidden in the common (empty-queue) case, so
          // zero clutter. When set mutations are queued/failed it shows a small
          // tappable "Pending N" chip that force-flushes the queue. Bound to the
          // app-wide coordinator notifier — render + retry only, no log changes.
          ValueListenableBuilder<int>(
            valueListenable: OfflineSyncCoordinator.instance.pendingCount,
            builder: (context, pending, _) {
              if (pending <= 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: SyncStatusChip(
                    pendingCount: pending,
                    onRetry: _retryOfflineSync,
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              // Only this clock text rebuilds each second; the exercise list
              // below stays out of the per-second rebuild.
              child: ValueListenableBuilder<Duration>(
                valueListenable: _elapsed,
                builder: (context, elapsed, _) {
                  final minutes = elapsed.inMinutes
                      .remainder(60)
                      .toString()
                      .padLeft(2, '0');
                  final seconds = elapsed.inSeconds
                      .remainder(60)
                      .toString()
                      .padLeft(2, '0');
                  final hours = elapsed.inHours;
                  return Text(
                    hours > 0
                        ? '$hours:$minutes:$seconds'
                        : '$minutes:$seconds',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: ZveltTokens.info,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == w.exercises.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ZveltSecondaryButton(
                label: 'Add exercise',
                icon: AppIcons.plus,
                onTap: _addExercise,
              ),
            );
          }
          final we = w.exercises[index];
          return _ExerciseCard(
            we: we,
            prSetIds: _prSetIds,
            progression: _progression[we.exerciseId],
            onLogPendingSet: (s) => _logPendingSet(we, s),
            onAddSet: () => _addSet(we),
            onSaveSet: (set, weightKg, reps) => _saveSetInline(
              we,
              set,
              weightKg: weightKg,
              reps: reps,
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Unobtrusive prescribed-rest countdown; collapses to nothing when
            // no countdown is active (no prescription / skipped / not resting).
            // Scoped to its own notifier so it never rebuilds the exercise list.
            ValueListenableBuilder<RestCountdown?>(
              valueListenable: _restCountdown,
              builder: (context, countdown, _) {
                if (countdown == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: _RestCountdownBanner(
                    countdown: countdown,
                    onSkip: _skipRestCountdown,
                    onExtend: _extendRestCountdown,
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: _complete,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                child: const Text('Complete workout'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExitConfirm() {
    // Capture the tracker screen's Navigator up-front so we don't reach for
    // `context` across the async discard below.
    final screenNavigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: const Text('Discard workout?'),
        content: const Text('Progress will not be saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ZveltTokens.error),
            onPressed: () async {
              Navigator.pop(ctx);
              // Abandon BEFORE leaving the screen so the next launch doesn't
              // re-prompt to resume this workout (P1.11). Awaiting (instead of
              // fire-and-forget) ensures an offline/slow discard isn't silently
              // lost; discardWorkout already swallows network errors internally,
              // and .catchError logs any unexpected throw so the pop still runs.
              await _service.discardWorkout(widget.workoutId).catchError(
                  (Object e) => debugPrint('discardWorkout failed: $e'));
              if (screenNavigator.mounted) screenNavigator.pop();
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({
    required this.we,
    required this.onLogPendingSet,
    required this.onAddSet,
    required this.onSaveSet,
    required this.prSetIds,
    this.progression,
  });

  final WorkoutExerciseDto we;
  final void Function(WorkoutSetDto s) onLogPendingSet;
  final VoidCallback onAddSet;
  final Future<void> Function(WorkoutSetDto set, double weightKg, int reps)
      onSaveSet;

  /// Ids of sets flagged as a personal record this session (parent-computed).
  final Set<String> prSetIds;

  /// Suggested next load for this exercise (brief §8.3), or null while loading.
  final ProgressionSuggestion? progression;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  final Map<String, TextEditingController> _kgCtrls = {};
  final Map<String, TextEditingController> _repsCtrls = {};
  final Map<String, FocusNode> _kgFocus = {};
  final Map<String, FocusNode> _repsFocus = {};
  final Set<String> _savingSetIds = <String>{};
  // Inline validation errors keyed by set.id.
  final Map<String, String?> _kgErrors = {};
  final Map<String, String?> _repsErrors = {};

  @override
  void dispose() {
    for (final c in _kgCtrls.values) {
      c.dispose();
    }
    for (final c in _repsCtrls.values) {
      c.dispose();
    }
    for (final f in _kgFocus.values) {
      f.dispose();
    }
    for (final f in _repsFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Returns null if [raw] is empty (no error shown until user types something)
  /// or a parsed value in range; otherwise returns the human-readable error.
  static (double?, String?) _validateKg(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return (null, null);
    final v = double.tryParse(trimmed);
    if (v == null) return (null, 'Weight must be a number');
    if (v < kSetWeightMinKg || v > kSetWeightMaxKg) {
      return (null, 'Weight must be 0–500 kg');
    }
    return (v, null);
  }

  static (int?, String?) _validateReps(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return (null, null);
    final v = int.tryParse(trimmed);
    if (v == null) return (null, 'Reps must be a whole number');
    if (v < kSetRepsMin || v > kSetRepsMax) {
      return (null, 'Reps must be 1–50');
    }
    return (v, null);
  }

  TextEditingController _kgCtrlFor(WorkoutSetDto set) {
    return _kgCtrls.putIfAbsent(
      set.id,
      () {
        final c = TextEditingController(
          text: set.weightKg > 0
              ? set.weightKg.toStringAsFixed(set.weightKg % 1 == 0 ? 0 : 1)
              : '',
        );
        c.addListener(() {
          final (_, err) = _validateKg(c.text);
          if (!mounted) return;
          setState(() => _kgErrors[set.id] = err);
        });
        return c;
      },
    );
  }

  TextEditingController _repsCtrlFor(WorkoutSetDto set) {
    return _repsCtrls.putIfAbsent(
      set.id,
      () {
        final c = TextEditingController(
          text: set.reps > 0 ? '${set.reps}' : '',
        );
        c.addListener(() {
          final (_, err) = _validateReps(c.text);
          if (!mounted) return;
          setState(() => _repsErrors[set.id] = err);
        });
        return c;
      },
    );
  }

  FocusNode _kgFocusFor(WorkoutSetDto set) {
    return _kgFocus.putIfAbsent(set.id, () => FocusNode());
  }

  FocusNode _repsFocusFor(WorkoutSetDto set) {
    return _repsFocus.putIfAbsent(set.id, () => FocusNode());
  }

  /// True iff the user's current inline input passes bounded validation
  /// AND is non-empty for the fields required by [mode]. Used to enable/
  /// disable the inline "done" glyph.
  bool _isSetInputValid(WorkoutSetDto set, SetLogMode mode) {
    final (reps, repsErr) = _validateReps(_repsCtrlFor(set).text);
    if (repsErr != null || reps == null) return false;
    if (mode == SetLogMode.weighted || mode == SetLogMode.timeSeconds) {
      final (kg, kgErr) = _validateKg(_kgCtrlFor(set).text);
      if (kgErr != null || kg == null) return false;
    }
    return true;
  }

  Future<void> _submitSet(WorkoutSetDto set) async {
    if (_savingSetIds.contains(set.id)) return;
    final mode = setLogModeForExercise(widget.we.exercise);

    final (parsedReps, repsErr) = _validateReps(_repsCtrlFor(set).text);
    if (repsErr != null || parsedReps == null) {
      setState(() => _repsErrors[set.id] = repsErr ?? 'Reps must be 1–50');
      return;
    }

    double kg = 0.0;
    if (mode == SetLogMode.weighted || mode == SetLogMode.timeSeconds) {
      final (parsedKg, kgErr) = _validateKg(_kgCtrlFor(set).text);
      if (kgErr != null || parsedKg == null) {
        setState(() => _kgErrors[set.id] = kgErr ?? 'Weight must be 0–500 kg');
        return;
      }
      kg = parsedKg;
    }

    final sorted = [...widget.we.sets]
      ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
    WorkoutSetDto? nextPending;
    for (final s in sorted) {
      if (s.setIndex > set.setIndex && !s.isCompleted) {
        nextPending = s;
        break;
      }
    }

    setState(() => _savingSetIds.add(set.id));
    try {
      await widget.onSaveSet(set, kg, parsedReps);
    } finally {
      if (mounted) {
        setState(() => _savingSetIds.remove(set.id));
      }
    }
    if (!mounted) return;

    if (nextPending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (mode == SetLogMode.bodyweightReps) {
          FocusScope.of(context).requestFocus(_repsFocusFor(nextPending!));
        } else {
          FocusScope.of(context).requestFocus(_kgFocusFor(nextPending!));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final we = widget.we;
    final sortedSets = [...we.sets]
      ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
    final mode = setLogModeForExercise(we.exercise);
    final showKg = mode != SetLogMode.bodyweightReps;

    // Single linear pass over the already-sorted sets: for each set, the "PREV"
    // value is the most recent completed set that precedes it. Tracking the last
    // completed set as we walk avoids the previous O(n^2) double-filter per row.
    final prevLabels = <String, String>{};
    WorkoutSetDto? lastCompleted;
    for (final s in sortedSets) {
      prevLabels[s.id] = lastCompleted == null
          ? '-'
          : showKg
              ? '${lastCompleted.weightKg.toStringAsFixed(lastCompleted.weightKg % 1 == 0 ? 0 : 1)}×${lastCompleted.reps}'
              : '${lastCompleted.reps}';
      if (s.isCompleted) lastCompleted = s;
    }

    // Seed weight for the plate calculator: prefer the weight the user is about
    // to load (first pending set's typed kg), else the last completed weight,
    // else a bare bar.
    double plateSeed = 20;
    for (final s in sortedSets) {
      if (s.isCompleted && s.weightKg > 0) plateSeed = s.weightKg;
    }
    final pending = sortedSets.where((s) => !s.isCompleted);
    if (pending.isNotEmpty) {
      final typed = double.tryParse(_kgCtrlFor(pending.first).text);
      if (typed != null && typed > 0) plateSeed = typed;
    }

    return Card(
      color: ZveltTokens.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    we.exercise.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ZveltTokens.text,
                        ),
                  ),
                ),
                if (showKg)
                  IconButton(
                    tooltip: 'Plate calculator',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      Icons.fitness_center,
                      color: ZveltTokens.text2,
                      size: 20,
                    ),
                    onPressed: () => showPlateCalculator(context, plateSeed),
                  ),
                IconButton(
                  tooltip: 'View reference GIF',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(
                    AppIcons.play,
                    color: ZveltTokens.text2,
                    size: 22,
                  ),
                  onPressed: () => ExerciseGifDialog.show(
                    context,
                    exerciseName: we.exercise.name,
                  ),
                ),
              ],
            ),
            if (widget.progression?.suggestedWeightKg != null &&
                widget.progression!.source != 'no_history') ...[
              const SizedBox(height: 8),
              _ProgressionChip(suggestion: widget.progression!),
            ],
            if (we.repRangeHint != null && we.repRangeHint!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${AppStrings.targetReps}: ${we.repRangeHint}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ZveltTokens.info,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            if (we.restSecondsDefault != null &&
                we.restSecondsDefault! > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Rest ~${we.restSecondsDefault}s',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: ZveltTokens.text2),
              ),
            ],
            if (sortedSets.isNotEmpty) const SizedBox(height: 10),
            if (sortedSets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                child: Row(
                  children: [
                    SizedBox(
                        width: 44,
                        child: Text('SET',
                            style: TextStyle(
                                color: ZveltTokens.text2,
                                fontSize: 11,
                                fontWeight: FontWeight.w600))),
                    SizedBox(
                        width: 56,
                        child: Text('PREV',
                            style: TextStyle(
                                color: ZveltTokens.text2,
                                fontSize: 11,
                                fontWeight: FontWeight.w600))),
                    Expanded(
                        child: Text('KG',
                            style: TextStyle(
                                color: ZveltTokens.text2,
                                fontSize: 11,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('REPS',
                            style: TextStyle(
                                color: ZveltTokens.text2,
                                fontSize: 11,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ...sortedSets.map((s) {
              final prevLabel = prevLabels[s.id] ?? '-';

              if (!s.isCompleted) {
                // Touch the controllers so listeners are wired even before
                // the user types (otherwise `_isSetInputValid` returns false
                // for prefilled values without ever flipping back to true).
                _kgCtrlFor(s);
                _repsCtrlFor(s);
                final kgError = _kgErrors[s.id];
                final repsError = _repsErrors[s.id];
                final inputValid = _isSetInputValid(s, mode);
                final inlineError = kgError ?? repsError;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: ZveltTokens.bg2,
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: ZveltTokens.s2, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${s.setIndex + 1}',
                                style: ZType.num_.copyWith(
                                    color: ZveltTokens.text,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                prevLabel,
                                style: ZType.num_.copyWith(
                                    color: ZveltTokens.text2, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              child: showKg
                                  ? TextField(
                                      controller: _kgCtrlFor(s),
                                      focusNode: _kgFocusFor(s),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      textInputAction: TextInputAction.next,
                                      decoration: InputDecoration(
                                        hintText: '0',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 10),
                                        // Underline-only color flip; full error text shown below.
                                        errorText: kgError == null ? null : '',
                                        errorStyle: const TextStyle(
                                            height: 0, fontSize: 0),
                                      ),
                                    )
                                  : Text(
                                      '-',
                                      style:
                                          TextStyle(color: ZveltTokens.text2),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _repsCtrlFor(s),
                                focusNode: _repsFocusFor(s),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submitSet(s),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  errorText: repsError == null ? null : '',
                                  errorStyle:
                                      const TextStyle(height: 0, fontSize: 0),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: Center(
                                child: _WorkoutSetDoneGlyph(
                                  completed: false,
                                  loading: _savingSetIds.contains(s.id),
                                  // Disable until inputs are in-bounds; defense-in-depth
                                  // re-checks happen inside `_submitSet` and the service.
                                  onTap:
                                      inputValid ? () => _submitSet(s) : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (inlineError != null)
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(44 + 56, 2, 4, 4),
                            child: Text(
                              inlineError,
                              style: const TextStyle(
                                  color: ZveltTokens.error, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  decoration: BoxDecoration(
                    color: ZveltTokens.bg2.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: ZveltTokens.s2, vertical: ZveltTokens.s2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${s.setIndex + 1}',
                                  style: ZType.num_.copyWith(
                                      color: ZveltTokens.text, fontSize: 13),
                                ),
                                if (widget.prSetIds.contains(s.id)) ...[
                                  const SizedBox(width: 3),
                                  const Icon(AppIcons.trophy,
                                      size: 12, color: ZveltTokens.warn),
                                ],
                              ],
                            ),
                            if (s.tag != 'WORK') _SetTagBadge(tag: s.tag),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          prevLabel,
                          style: ZType.num_
                              .copyWith(color: ZveltTokens.text2, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          showKg
                              ? s.weightKg
                                  .toStringAsFixed(s.weightKg % 1 == 0 ? 0 : 1)
                              : '-',
                          style: ZType.num_
                              .copyWith(color: ZveltTokens.text, fontSize: 13),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: ZveltTokens.s2),
                      Expanded(
                        child: Text(
                          '${s.reps}',
                          style: ZType.num_
                              .copyWith(color: ZveltTokens.text, fontSize: 13),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(
                        width: 44,
                        child: Center(
                          child: _WorkoutSetDoneGlyph(
                            completed: true,
                            loading: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onAddSet,
              icon: const Icon(AppIcons.plus, size: 18),
              label: const Text(AppStrings.logSet),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bifat serie: nelogată = cerc ridicat (relief); logată = plat, turcoaz + check alb.
/// Auto-progression hint (brief §8.3): the suggested next working load + a
/// tap-for-why explanation (explainability §3). Color/icon reflect the source.
class _ProgressionChip extends StatelessWidget {
  const _ProgressionChip({required this.suggestion});

  final ProgressionSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final kg = suggestion.suggestedWeightKg!;
    final (Color color, IconData icon, String label) =
        switch (suggestion.source) {
      'deload' => (ZveltTokens.warn, AppIcons.arrow_small_down, 'Deload'),
      'hold' => (ZveltTokens.text2, AppIcons.minus, 'Hold'),
      _ => (ZveltTokens.success, AppIcons.arrow_small_up, 'Next'),
    };
    final kgStr = kg == kg.roundToDouble()
        ? kg.toStringAsFixed(0)
        : kg.toStringAsFixed(1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        onTap: suggestion.reason.isEmpty
            ? null
            : () {
                final m = ScaffoldMessenger.of(context);
                m.clearSnackBars();
                m.showSnackBar(SnackBar(
                  content: Text(suggestion.reason),
                  duration: const Duration(seconds: 4),
                ));
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                '$label $kgStr kg',
                style: ZType.bodyS
                    .copyWith(color: color, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Icon(AppIcons.info,
                  size: 12, color: color.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny chip on a set row whose tag isn't a normal WORK set (warmup / drop) —
/// these are excluded from e1RM/PR server-side (brief §8).
class _SetTagBadge extends StatelessWidget {
  const _SetTagBadge({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final label = tag == 'WARMUP' ? 'WARM' : (tag == 'DROP' ? 'DROP' : tag);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: ZveltTokens.warn.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: ZveltTokens.fontMono,
          fontSize: 8,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: ZveltTokens.warn,
        ),
      ),
    );
  }
}

class _WorkoutSetDoneGlyph extends StatelessWidget {
  const _WorkoutSetDoneGlyph({
    required this.completed,
    required this.loading,
    this.onTap,
  });

  final bool completed;
  final bool loading;
  final VoidCallback? onTap;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: _size,
        height: _size,
        child: Padding(
          padding: EdgeInsets.all(7),
          child: CircularProgressIndicator(
              strokeWidth: 2, color: ZveltTokens.info),
        ),
      );
    }

    if (completed) {
      return Tooltip(
        message: 'Logged',
        child: Container(
          width: _size,
          height: _size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ZveltTokens.success,
          ),
          child:
              const Icon(AppIcons.check, color: ZveltTokens.onBrand, size: 22),
        ),
      );
    }

    return Tooltip(
      message: 'Log set',
      child: Material(
        elevation: 3.5,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        surfaceTintColor: Colors.transparent,
        color: ZveltTokens.bg,
        shape: CircleBorder(
          side: BorderSide(color: ZveltTokens.border.withValues(alpha: 0.95)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: _size,
            height: _size,
            child: Icon(
              AppIcons.check,
              color: ZveltTokens.text2.withValues(alpha: 0.72),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// Immutable snapshot of a running rest countdown. Lives in a [ValueNotifier]
/// driven by [_WorkoutTrackerScreenState] so the banner can rebuild once a
/// second without touching the exercise list. Carries the prescription so the
/// banner can show "45s / 90s" and so adherence is derivable later.
@immutable
class RestCountdown {
  const RestCountdown({
    required this.exerciseName,
    required this.prescribedSeconds,
    required this.remainingSeconds,
  });

  final String exerciseName;
  final int prescribedSeconds;
  final int remainingSeconds;

  bool get isDone => remainingSeconds <= 0;

  RestCountdown copyWith({int? remainingSeconds}) => RestCountdown(
        exerciseName: exerciseName,
        prescribedSeconds: prescribedSeconds,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      );
}

/// Format a non-negative second count as `m:ss` (e.g. 90 → "1:30", 45 → "0:45").
String _formatRestClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final rem = (s % 60).toString().padLeft(2, '0');
  return '$m:$rem';
}

/// Compact, dismissible rest-timer banner shown between sets. Skip clears it;
/// "+15s" extends the countdown. Purely presentational — all state mutation is
/// delegated to the parent via [onSkip] / [onExtend].
class _RestCountdownBanner extends StatelessWidget {
  const _RestCountdownBanner({
    required this.countdown,
    required this.onSkip,
    required this.onExtend,
  });

  final RestCountdown countdown;
  final VoidCallback onSkip;
  final VoidCallback onExtend;

  @override
  Widget build(BuildContext context) {
    final done = countdown.isDone;
    final accent = done ? ZveltTokens.success : ZveltTokens.info;
    return Semantics(
      liveRegion: true,
      label: done
          ? 'Rest over for ${countdown.exerciseName}'
          : 'Resting, ${countdown.remainingSeconds} seconds remaining of '
              '${countdown.prescribedSeconds} prescribed',
      child: Container(
        decoration: BoxDecoration(
          color: ZveltTokens.bg2,
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s4,
          vertical: ZveltTokens.s2,
        ),
        child: Row(
          children: [
            Icon(AppIcons.clock, size: 18, color: accent),
            const SizedBox(width: ZveltTokens.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    done ? 'Rest over' : 'Resting',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ZveltTokens.text2,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    '${_formatRestClock(countdown.remainingSeconds)} / '
                    '${_formatRestClock(countdown.prescribedSeconds)}',
                    style: ZType.num_.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onExtend,
              style: TextButton.styleFrom(
                foregroundColor: ZveltTokens.text2,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2),
              ),
              child: const Text('+15s'),
            ),
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: accent,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2),
              ),
              child: const Text('Skip'),
            ),
          ],
        ),
      ),
    );
  }
}
